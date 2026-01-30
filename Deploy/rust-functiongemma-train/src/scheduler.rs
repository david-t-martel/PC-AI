/// Learning rate scheduler with warmup support
use std::f64::consts::PI;

/// Type of learning rate schedule after warmup
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum SchedulerType {
    /// Cosine annealing: 0.5 * (1 + cos(π * progress))
    Cosine,
    /// Linear decay from max_lr to min_lr
    Linear,
    /// Constant learning rate after warmup
    Constant,
}

/// Configuration for learning rate scheduler
#[derive(Debug, Clone, Copy)]
pub struct SchedulerConfig {
    /// Type of scheduler to use
    pub scheduler_type: SchedulerType,
    /// Number of warmup steps (linear ramp from min_lr to max_lr)
    pub warmup_steps: usize,
    /// Total training steps
    pub total_steps: usize,
    /// Minimum learning rate
    pub min_lr: f64,
    /// Maximum learning rate (reached at end of warmup)
    pub max_lr: f64,
}

impl Default for SchedulerConfig {
    fn default() -> Self {
        Self {
            scheduler_type: SchedulerType::Cosine,
            warmup_steps: 100,
            total_steps: 1000,
            min_lr: 1e-6,
            max_lr: 1e-4,
        }
    }
}

/// Learning rate scheduler implementing warmup + decay strategies
pub struct LRScheduler {
    config: SchedulerConfig,
}

impl LRScheduler {
    /// Create a new learning rate scheduler
    pub fn new(config: SchedulerConfig) -> Self {
        assert!(
            config.warmup_steps <= config.total_steps,
            "warmup_steps must be <= total_steps"
        );
        assert!(config.min_lr >= 0.0, "min_lr must be non-negative");
        assert!(config.max_lr >= config.min_lr, "max_lr must be >= min_lr");

        Self { config }
    }

    /// Get learning rate for a given step
    pub fn get_lr(&self, step: usize) -> f64 {
        if step <= self.config.warmup_steps {
            // Linear warmup from min_lr to max_lr
            self.warmup_lr(step)
        } else {
            // Apply decay schedule
            self.decay_lr(step)
        }
    }

    /// Calculate learning rate during warmup phase
    fn warmup_lr(&self, step: usize) -> f64 {
        if self.config.warmup_steps == 0 {
            return self.config.max_lr;
        }

        // Linear interpolation from min_lr to max_lr
        let progress = step as f64 / self.config.warmup_steps as f64;
        self.config.min_lr + (self.config.max_lr - self.config.min_lr) * progress
    }

    /// Calculate learning rate during decay phase
    fn decay_lr(&self, step: usize) -> f64 {
        let decay_steps = self.config.total_steps - self.config.warmup_steps;
        if decay_steps == 0 {
            return self.config.max_lr;
        }

        // Progress through decay phase (0.0 to 1.0)
        let decay_step = step - self.config.warmup_steps;
        let progress = (decay_step as f64 / decay_steps as f64).min(1.0);

        match self.config.scheduler_type {
            SchedulerType::Cosine => {
                // Cosine annealing: 0.5 * (1 + cos(π * progress))
                let cosine_factor = 0.5 * (1.0 + (PI * progress).cos());
                self.config.min_lr + (self.config.max_lr - self.config.min_lr) * cosine_factor
            }
            SchedulerType::Linear => {
                // Linear decay from max_lr to min_lr
                self.config.max_lr - (self.config.max_lr - self.config.min_lr) * progress
            }
            SchedulerType::Constant => {
                // Constant at max_lr after warmup
                self.config.max_lr
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_warmup_boundaries() {
        let config = SchedulerConfig {
            scheduler_type: SchedulerType::Cosine,
            warmup_steps: 100,
            total_steps: 1000,
            min_lr: 1e-6,
            max_lr: 1e-4,
        };
        let scheduler = LRScheduler::new(config);

        // Step 0 should be at min_lr
        assert!((scheduler.get_lr(0) - 1e-6).abs() < 1e-10);

        // Step warmup_steps should be at max_lr
        assert!((scheduler.get_lr(100) - 1e-4).abs() < 1e-10);
    }

    #[test]
    fn test_cosine_symmetry() {
        let config = SchedulerConfig {
            scheduler_type: SchedulerType::Cosine,
            warmup_steps: 0,
            total_steps: 1000,
            min_lr: 0.0,
            max_lr: 1.0,
        };
        let scheduler = LRScheduler::new(config);

        // Cosine should be symmetric around midpoint
        // lr(t) + lr(1-t) = max_lr + min_lr for symmetric progress points
        let lr_250 = scheduler.get_lr(250);
        let lr_750 = scheduler.get_lr(750);
        let sum = lr_250 + lr_750;
        let expected_sum = config.max_lr + config.min_lr;
        assert!((sum - expected_sum).abs() < 1e-10);
    }

    #[test]
    #[should_panic(expected = "warmup_steps must be <= total_steps")]
    fn test_invalid_warmup_steps() {
        let config = SchedulerConfig {
            scheduler_type: SchedulerType::Cosine,
            warmup_steps: 1000,
            total_steps: 100,
            min_lr: 1e-6,
            max_lr: 1e-4,
        };
        LRScheduler::new(config);
    }

    #[test]
    #[should_panic(expected = "max_lr must be >= min_lr")]
    fn test_invalid_lr_range() {
        let config = SchedulerConfig {
            scheduler_type: SchedulerType::Cosine,
            warmup_steps: 100,
            total_steps: 1000,
            min_lr: 1e-4,
            max_lr: 1e-6,
        };
        LRScheduler::new(config);
    }
}
