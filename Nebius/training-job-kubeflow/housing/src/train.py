import os
import time
import torch
import torch.distributed as dist
from torch import nn
from torch.nn.parallel import DistributedDataParallel as DDP
from torch.utils.data import Dataset, DataLoader
from torch.utils.data.distributed import DistributedSampler
from sklearn.datasets import fetch_california_housing
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

from prometheus_client import CollectorRegistry, Gauge, push_to_gateway


def setup_distributed():
    world_size = int(os.environ.get("WORLD_SIZE", "1"))
    rank = int(os.environ.get("RANK", "0"))
    local_rank = int(os.environ.get("LOCAL_RANK", "0"))
    if world_size > 1:
        dist.init_process_group(backend="nccl")
        torch.cuda.set_device(local_rank)
        device = torch.device("cuda", local_rank)
    else:
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    return device, world_size, rank, local_rank


def setup_metrics():
    pushgateway_url = os.environ.get("PUSHGATEWAY_URL", "")
    if not pushgateway_url:
        return None, {}

    registry = CollectorRegistry()
    job_name = os.environ.get("JOB_NAME", "housing-price-train")
    labels = ["job_name", "model"]
    label_values = [job_name, "housing-mlp"]

    gauges = {
        "loss": Gauge("training_loss", "Training loss", labels, registry=registry),
        "val_loss": Gauge("training_val_loss", "Validation loss", labels, registry=registry),
        "epoch": Gauge("training_epoch", "Current epoch", labels, registry=registry),
        "step": Gauge("training_step", "Current step", labels, registry=registry),
        "throughput": Gauge("training_throughput_samples_per_sec", "Training throughput", labels, registry=registry),
        "gpu_mem": Gauge("training_gpu_memory_used_mb", "GPU memory used (MB)", labels, registry=registry),
    }

    return registry, {"gauges": gauges, "label_values": label_values, "url": pushgateway_url, "job": job_name}


def push_metrics(metrics_ctx, **kwargs):
    if not metrics_ctx:
        return
    gauges = metrics_ctx["gauges"]
    lv = metrics_ctx["label_values"]
    for key, value in kwargs.items():
        if key in gauges:
            gauges[key].labels(*lv).set(value)
    try:
        push_to_gateway(metrics_ctx["url"], job=metrics_ctx["job"], registry=metrics_ctx.get("registry"))
    except Exception:
        pass


class HousingDataset(Dataset):
    def __init__(self, features, targets):
        self.x = torch.tensor(features, dtype=torch.float32)
        self.y = torch.tensor(targets, dtype=torch.float32).unsqueeze(1)

    def __len__(self):
        return self.x.shape[0]

    def __getitem__(self, idx):
        return self.x[idx], self.y[idx]


class MLP(nn.Module):
    def __init__(self, in_dim):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(in_dim, 128),
            nn.ReLU(),
            nn.Linear(128, 64),
            nn.ReLU(),
            nn.Linear(64, 1),
        )

    def forward(self, x):
        return self.net(x)


def main():
    torch.backends.cuda.matmul.allow_tf32 = True

    device, world_size, rank, local_rank = setup_distributed()

    registry = None
    metrics_ctx = {}
    if rank == 0:
        registry, metrics_ctx = setup_metrics()
        if registry:
            metrics_ctx["registry"] = registry

    epochs = int(os.environ.get("EPOCHS", "20"))
    batch_size = int(os.environ.get("BATCH_SIZE", "256"))
    lr = float(os.environ.get("LR", "1e-3"))

    if rank == 0:
        print(f"Using device={device}, world_size={world_size}, batch_size={batch_size}")

    data = fetch_california_housing()
    X = data.data
    y = data.target

    X_train, X_val, y_train, y_val = train_test_split(
        X, y, test_size=0.1, random_state=42
    )

    scaler = StandardScaler()
    X_train = scaler.fit_transform(X_train)
    X_val = scaler.transform(X_val)

    train_ds = HousingDataset(X_train, y_train)
    val_ds = HousingDataset(X_val, y_val)

    train_sampler = DistributedSampler(train_ds) if world_size > 1 else None
    train_loader = DataLoader(
        train_ds,
        batch_size=batch_size,
        sampler=train_sampler,
        shuffle=train_sampler is None,
        num_workers=2,
        pin_memory=True,
    )

    val_loader = DataLoader(
        val_ds,
        batch_size=batch_size,
        shuffle=False,
        num_workers=2,
        pin_memory=True,
    )

    model = MLP(in_dim=X_train.shape[1]).to(device)
    if world_size > 1:
        model = DDP(model, device_ids=[local_rank], output_device=local_rank)

    criterion = nn.MSELoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=lr)

    start = time.time()
    global_step = 0
    for epoch in range(epochs):
        if train_sampler is not None:
            train_sampler.set_epoch(epoch)

        model.train()
        running_loss = 0.0
        epoch_samples = 0
        epoch_start = time.time()
        for xb, yb in train_loader:
            xb = xb.to(device, non_blocking=True)
            yb = yb.to(device, non_blocking=True)

            optimizer.zero_grad(set_to_none=True)
            preds = model(xb)
            loss = criterion(preds, yb)
            loss.backward()
            optimizer.step()
            running_loss += loss.item() * xb.size(0)
            epoch_samples += xb.size(0)
            global_step += 1

        if rank == 0:
            train_loss = running_loss / len(train_ds)
            elapsed_epoch = time.time() - epoch_start
            throughput = epoch_samples / elapsed_epoch if elapsed_epoch > 0 else 0
            gpu_mem = torch.cuda.memory_allocated(device) / 1024 / 1024
            print(f"Epoch {epoch+1}/{epochs} - train_loss: {train_loss:.4f} - throughput: {throughput:.0f} samples/s")
            push_metrics(metrics_ctx, loss=train_loss, epoch=epoch + 1, step=global_step, throughput=throughput, gpu_mem=gpu_mem)

        model.eval()
        val_loss_sum = 0.0
        with torch.no_grad():
            for xb, yb in val_loader:
                xb = xb.to(device, non_blocking=True)
                yb = yb.to(device, non_blocking=True)
                preds = model(xb)
                loss = criterion(preds, yb)
                val_loss_sum += loss.item() * xb.size(0)

        if rank == 0:
            val_loss = val_loss_sum / len(val_ds)
            print(f"Epoch {epoch+1}/{epochs} - val_loss: {val_loss:.4f}")
            push_metrics(metrics_ctx, val_loss=val_loss)

    if rank == 0:
        elapsed = time.time() - start
        print(f"Training completed in {elapsed/60:.2f} minutes")

    if world_size > 1:
        dist.barrier()
        dist.destroy_process_group()


if __name__ == "__main__":
    main()
