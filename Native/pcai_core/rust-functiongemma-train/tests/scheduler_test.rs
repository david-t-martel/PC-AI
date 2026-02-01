use rust_functiongemma_train::scheduler::{LRScheduler, SchedulerConfig, SchedulerType};

#[test]
fn test_cosine_scheduler() {
    let config = SchedulerConfig {
        scheduler_type: SchedulerType::Cosine,
        warmup_steps: 100,
        total_steps: 1000,
        min_lr: 1e-6,
        max_lr: 1e-4,
    };
    let scheduler = LRScheduler::new(config);

    // Warmup phase - should be small at start
    assert!(scheduler.get_lr(0) < 1e-5);
    // End of warmup - should be at max_lr
    let lr_100 = scheduler.get_lr(100);
    assert!((lr_100 - 1e-4).abs() < 1e-7);
    // End of training - should be at min_lr
    let lr_1000 = scheduler.get_lr(1000);
    assert!((lr_1000 - 1e-6).abs() < 1e-8);
}

#[test]
fn test_linear_warmup() {
    let config = SchedulerConfig {
        scheduler_type: SchedulerType::Linear,
        warmup_steps: 100,
        total_steps: 1000,
        min_lr: 0.0,
        max_lr: 1e-4,
    };
    let scheduler = LRScheduler::new(config);
    let lr_50 = scheduler.get_lr(50);
    assert!((lr_50 - 5e-5).abs() < 1e-7);
}

#[test]
fn test_constant_scheduler() {
    let config = SchedulerConfig {
        scheduler_type: SchedulerType::Constant,
        warmup_steps: 100,
        total_steps: 1000,
        min_lr: 1e-6,
        max_lr: 1e-4,
    };
    let scheduler = LRScheduler::new(config);

    // During warmup
    let lr_50 = scheduler.get_lr(50);
    assert!((lr_50 - 5.05e-5).abs() < 1e-7);

    // After warmup, should be constant at max_lr
    let lr_200 = scheduler.get_lr(200);
    assert!((lr_200 - 1e-4).abs() < 1e-7);

    let lr_900 = scheduler.get_lr(900);
    assert!((lr_900 - 1e-4).abs() < 1e-7);
}

#[test]
fn test_warmup_boundary() {
    let config = SchedulerConfig {
        scheduler_type: SchedulerType::Cosine,
        warmup_steps: 100,
        total_steps: 1000,
        min_lr: 1e-6,
        max_lr: 1e-4,
    };
    let scheduler = LRScheduler::new(config);

    // At step 0, should be at min_lr
    let lr_0 = scheduler.get_lr(0);
    assert!((lr_0 - 1e-6).abs() < 1e-8);

    // Just before end of warmup
    let lr_99 = scheduler.get_lr(99);
    assert!(lr_99 < 1e-4);
    assert!(lr_99 > 9e-5);
}

#[test]
fn test_cosine_decay_midpoint() {
    let config = SchedulerConfig {
        scheduler_type: SchedulerType::Cosine,
        warmup_steps: 100,
        total_steps: 1000,
        min_lr: 1e-6,
        max_lr: 1e-4,
    };
    let scheduler = LRScheduler::new(config);

    // Midpoint of decay phase (step 550 = halfway between 100 and 1000)
    let lr_550 = scheduler.get_lr(550);
    // Should be approximately halfway between max and min
    let expected = (1e-4 + 1e-6) / 2.0;
    assert!((lr_550 - expected).abs() < 1e-5);
}

#[test]
fn test_linear_decay() {
    let config = SchedulerConfig {
        scheduler_type: SchedulerType::Linear,
        warmup_steps: 100,
        total_steps: 1000,
        min_lr: 1e-6,
        max_lr: 1e-4,
    };
    let scheduler = LRScheduler::new(config);

    // After warmup, linear decay
    // At step 550 (midpoint of decay), should be halfway between max and min
    let lr_550 = scheduler.get_lr(550);
    let expected = (1e-4 + 1e-6) / 2.0;
    assert!((lr_550 - expected).abs() < 1e-7);

    // End of training
    let lr_1000 = scheduler.get_lr(1000);
    assert!((lr_1000 - 1e-6).abs() < 1e-8);
}
