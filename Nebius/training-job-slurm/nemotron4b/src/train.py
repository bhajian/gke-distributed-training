import os
import time
import torch
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP
from torch.utils.data import DataLoader
from torch.utils.data.distributed import DistributedSampler
from datasets import load_dataset
from transformers import AutoTokenizer, AutoModelForCausalLM
from peft import LoraConfig, get_peft_model


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


def format_example(example):
    term = example.get("medical_term", "")
    desc = example.get("wiki_description", "")
    prompt = (
        "You are a helpful assistant that explains medical terms in plain language. "
        "This is for educational purposes only and not medical advice.\n\n"
        f"Term: {term}\nDefinition:"
    )
    text = prompt + " " + desc
    return {"text": text}


def tokenize_function(tokenizer, max_length):
    def _tokenize(example):
        out = tokenizer(
            example["text"],
            truncation=True,
            max_length=max_length,
            padding="max_length",
        )
        labels = out["input_ids"].copy()
        # Mask padding tokens
        labels = [lbl if m == 1 else -100 for lbl, m in zip(labels, out["attention_mask"])]
        out["labels"] = labels
        return out

    return _tokenize


def main():
    torch.backends.cuda.matmul.allow_tf32 = True

    device, world_size, rank, local_rank = setup_distributed()

    model_id = os.environ.get("MODEL_ID", "nvidia/NVIDIA-Nemotron-3-Nano-4B-BF16")
    max_steps = int(os.environ.get("MAX_STEPS", "200"))
    max_length = int(os.environ.get("MAX_SEQ_LEN", "512"))
    per_device_batch = int(os.environ.get("BATCH_SIZE", "1"))
    grad_accum = int(os.environ.get("GRAD_ACCUM", "8"))
    lr = float(os.environ.get("LR", "2e-4"))
    log_every = int(os.environ.get("LOG_EVERY", "10"))
    max_samples = int(os.environ.get("MAX_SAMPLES", "20000"))

    if rank == 0:
        print(
            f"Model={model_id} world_size={world_size} max_steps={max_steps} "
            f"max_length={max_length} batch={per_device_batch} grad_accum={grad_accum}"
        )

    dataset = load_dataset("dmedhi/wiki-medical-terms", split="train")
    dataset = dataset.shuffle(seed=42)
    if max_samples > 0:
        dataset = dataset.select(range(min(max_samples, len(dataset))))

    dataset = dataset.map(format_example, remove_columns=dataset.column_names)

    # Some Nemotron tokenizers fail to load with the fast Rust tokenizer.
    # Try fast first, then fall back to the Python tokenizer.
    try:
        tokenizer = AutoTokenizer.from_pretrained(model_id, use_fast=True, trust_remote_code=True)
    except Exception:
        tokenizer = AutoTokenizer.from_pretrained(model_id, use_fast=False, trust_remote_code=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    dataset = dataset.map(
        tokenize_function(tokenizer, max_length),
        remove_columns=dataset.column_names,
        num_proc=2,
    )

    dataset.set_format(type="torch", columns=["input_ids", "attention_mask", "labels"])

    sampler = DistributedSampler(dataset) if world_size > 1 else None
    dataloader = DataLoader(
        dataset,
        batch_size=per_device_batch,
        sampler=sampler,
        shuffle=sampler is None,
        drop_last=True,
    )

    model = AutoModelForCausalLM.from_pretrained(
        model_id,
        torch_dtype=torch.bfloat16,
        low_cpu_mem_usage=True,
        trust_remote_code=True,
    )
    # Disable gradient checkpointing to avoid DDP "marked ready twice" errors
    # (LoRA + MoE + checkpointing can trip DDP reducer).
    if hasattr(model, "gradient_checkpointing_disable"):
        model.gradient_checkpointing_disable()
    if hasattr(model, "config"):
        model.config.use_cache = False

    try:
        lora_config = LoraConfig(
            r=8,
            lora_alpha=16,
            lora_dropout=0.05,
            bias="none",
            task_type="CAUSAL_LM",
            target_modules="all-linear",
        )
        model = get_peft_model(model, lora_config)
    except Exception:
        # Fallback for older PEFT versions: target all Linear modules by name
        linear_module_names = set()
        for name, module in model.named_modules():
            if isinstance(module, torch.nn.Linear):
                linear_module_names.add(name.split(".")[-1])
        lora_config = LoraConfig(
            r=8,
            lora_alpha=16,
            lora_dropout=0.05,
            bias="none",
            task_type="CAUSAL_LM",
            target_modules=sorted(linear_module_names),
        )
        model = get_peft_model(model, lora_config)
    model.to(device)

    if world_size > 1:
        model = DDP(model, device_ids=[local_rank], output_device=local_rank, find_unused_parameters=True)
        # Static graph helps with DDP + checkpointing
        try:
            model._set_static_graph()
        except Exception:
            pass

    optimizer = torch.optim.AdamW(model.parameters(), lr=lr)

    model.train()
    step = 0
    optim_step = 0
    start = time.time()

    while optim_step < max_steps:
        if sampler is not None:
            sampler.set_epoch(optim_step)

        for batch in dataloader:
            for k in batch:
                batch[k] = batch[k].to(device, non_blocking=True)

            with torch.cuda.amp.autocast(dtype=torch.bfloat16):
                outputs = model(**batch)
                loss = outputs.loss / grad_accum

            loss.backward()
            step += 1

            if step % grad_accum == 0:
                optimizer.step()
                optimizer.zero_grad(set_to_none=True)
                optim_step += 1

                if rank == 0 and optim_step % log_every == 0:
                    print(f"step {optim_step}/{max_steps} - loss: {loss.item() * grad_accum:.4f}")

                if optim_step >= max_steps:
                    break

        if optim_step >= max_steps:
            break

    if rank == 0:
        elapsed = time.time() - start
        print(f"Fine-tuning completed in {elapsed/60:.2f} minutes")
        output_dir = "/workspace/output"
        os.makedirs(output_dir, exist_ok=True)
        model_to_save = model.module if hasattr(model, "module") else model
        model_to_save.save_pretrained(output_dir)
        tokenizer.save_pretrained(output_dir)
        print(f"Saved LoRA adapter to {output_dir}")

    if world_size > 1:
        dist.barrier()
        dist.destroy_process_group()


if __name__ == "__main__":
    main()
