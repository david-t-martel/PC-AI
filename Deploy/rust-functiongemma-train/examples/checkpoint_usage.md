# Checkpoint Save/Resume Usage

This document demonstrates how to use the checkpoint functionality in the rust-functiongemma-train crate.

## Basic Save and Load

```rust
use rust_functiongemma_train::checkpoint::Checkpoint;
use std::path::PathBuf;

// Create a checkpoint
let checkpoint = Checkpoint {
    epoch: 5,
    global_step: 1000,
    best_loss: 0.42,
    optimizer_state: vec![0.1, 0.2, 0.3], // Serialized optimizer weights
    rng_state: Some(12345), // For reproducibility
};

// Save to disk
let checkpoint_path = PathBuf::from("./checkpoints/checkpoint-1000");
checkpoint.save(&checkpoint_path)?;

// Load from disk
let loaded = Checkpoint::load(&checkpoint_path)?;
assert_eq!(loaded.global_step, 1000);
```

## Find Latest Checkpoint

```rust
use rust_functiongemma_train::checkpoint::Checkpoint;
use std::path::Path;

// Find the most recent checkpoint in a directory
let checkpoint_dir = Path::new("./checkpoints");
let latest = Checkpoint::find_latest(checkpoint_dir)?;

println!("Resuming from epoch {}, step {}", latest.epoch, latest.global_step);
```

## Checkpoint Cleanup

```rust
use rust_functiongemma_train::checkpoint::{Checkpoint, CheckpointConfig};
use std::path::PathBuf;

// Configure checkpoint management
let config = CheckpointConfig {
    output_dir: PathBuf::from("./checkpoints"),
    save_every_n_steps: 100,
    max_checkpoints: 5, // Keep only the 5 most recent checkpoints
};

// Clean up old checkpoints
Checkpoint::cleanup_old(&config)?;
```

## Training Loop Integration

```rust
use rust_functiongemma_train::checkpoint::{Checkpoint, CheckpointConfig};
use std::path::PathBuf;

fn training_loop() -> anyhow::Result<()> {
    let config = CheckpointConfig {
        output_dir: PathBuf::from("./checkpoints"),
        save_every_n_steps: 500,
        max_checkpoints: 3,
    };

    // Try to resume from latest checkpoint
    let (start_epoch, start_step) = if let Ok(checkpoint) = Checkpoint::find_latest(&config.output_dir) {
        println!("Resuming from checkpoint: epoch {}, step {}", checkpoint.epoch, checkpoint.global_step);
        // TODO: Restore optimizer state and RNG
        (checkpoint.epoch, checkpoint.global_step)
    } else {
        println!("Starting training from scratch");
        (0, 0)
    };

    let mut best_loss = f64::INFINITY;

    for epoch in start_epoch..10 {
        for step in 0..1000 {
            let global_step = epoch * 1000 + step;

            if global_step < start_step {
                continue; // Skip already processed steps
            }

            // Training step logic here...
            let current_loss = 0.5; // Placeholder

            // Save checkpoint periodically
            if global_step % config.save_every_n_steps == 0 {
                if current_loss < best_loss {
                    best_loss = current_loss;
                }

                let checkpoint = Checkpoint {
                    epoch,
                    global_step,
                    best_loss,
                    optimizer_state: vec![0.1, 0.2, 0.3], // TODO: Serialize actual optimizer
                    rng_state: Some(rand::random()), // TODO: Get actual RNG state
                };

                let checkpoint_path = config.output_dir.join(format!("checkpoint-{}", global_step));
                checkpoint.save(&checkpoint_path)?;

                // Clean up old checkpoints
                Checkpoint::cleanup_old(&config)?;
            }
        }
    }

    Ok(())
}
```

## Directory Structure

After saving checkpoints, your directory structure will look like:

```
checkpoints/
├── checkpoint-500/
│   └── metadata.json
├── checkpoint-1000/
│   └── metadata.json
└── checkpoint-1500/
    └── metadata.json
```

Each `metadata.json` contains:

```json
{
  "epoch": 2,
  "global_step": 1000,
  "best_loss": 0.42,
  "optimizer_state": [0.1, 0.2, 0.3],
  "rng_state": 12345
}
```

## Error Handling

```rust
use rust_functiongemma_train::checkpoint::Checkpoint;

// Handle missing checkpoints gracefully
match Checkpoint::find_latest(&checkpoint_dir) {
    Ok(checkpoint) => {
        println!("Found checkpoint at step {}", checkpoint.global_step);
    }
    Err(e) => {
        println!("No checkpoint found, starting fresh: {}", e);
    }
}
```

## Best Practices

1. **Save periodically**: Use `save_every_n_steps` to balance between resume granularity and disk I/O overhead
2. **Limit checkpoint count**: Use `max_checkpoints` to prevent disk space exhaustion
3. **Save on best loss**: Always update `best_loss` when validation improves
4. **Store RNG state**: Include RNG state for fully reproducible training
5. **Validate on load**: Test that loaded checkpoints can be used before continuing training
