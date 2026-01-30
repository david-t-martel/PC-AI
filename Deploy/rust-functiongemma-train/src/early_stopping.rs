/// Configuration for early stopping during training.
#[derive(Debug, Clone)]
pub struct EarlyStoppingConfig {
    /// Number of epochs with no improvement after which training will be stopped.
    pub patience: usize,
    /// Minimum change in monitored value to qualify as an improvement.
    /// Improvement is defined as: best_loss - current_loss > min_delta
    pub min_delta: f64,
}

impl Default for EarlyStoppingConfig {
    fn default() -> Self {
        Self {
            patience: 5,
            min_delta: 0.001,
        }
    }
}

/// Early stopping monitor to prevent overfitting.
///
/// Tracks validation loss and stops training when loss stops improving
/// for a specified number of epochs (patience).
#[derive(Debug)]
pub struct EarlyStopping {
    config: EarlyStoppingConfig,
    best_loss: f64,
    counter: usize,
}

impl EarlyStopping {
    /// Creates a new early stopping monitor with the given configuration.
    ///
    /// # Arguments
    /// * `config` - Early stopping configuration (patience and min_delta)
    ///
    /// # Returns
    /// A new `EarlyStopping` instance with best_loss initialized to f64::MAX
    pub fn new(config: EarlyStoppingConfig) -> Self {
        Self {
            config,
            best_loss: f64::MAX,
            counter: 0,
        }
    }

    /// Checks if training should stop based on validation loss.
    ///
    /// # Arguments
    /// * `val_loss` - Current validation loss value
    ///
    /// # Returns
    /// `true` if training should stop (patience exceeded), `false` otherwise
    ///
    /// # Behavior
    /// - If current loss is better than best_loss by at least min_delta, resets counter
    /// - Otherwise, increments counter
    /// - Returns true when counter reaches patience
    pub fn should_stop(&mut self, val_loss: f64) -> bool {
        // Check if we have improvement (current loss is better than best by at least min_delta)
        let improvement = self.best_loss - val_loss;

        if improvement > self.config.min_delta {
            // Significant improvement - update best and reset counter
            self.best_loss = val_loss;
            self.counter = 0;
            false
        } else {
            // No significant improvement - increment counter
            self.counter += 1;
            self.counter >= self.config.patience
        }
    }

    /// Returns the best (lowest) validation loss seen so far.
    pub fn best_loss(&self) -> f64 {
        self.best_loss
    }

    /// Returns the current patience counter value.
    pub fn counter(&self) -> usize {
        self.counter
    }

    /// Resets the early stopping state to initial values.
    pub fn reset(&mut self) {
        self.best_loss = f64::MAX;
        self.counter = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_initial_state() {
        let config = EarlyStoppingConfig {
            patience: 3,
            min_delta: 0.01,
        };
        let stopper = EarlyStopping::new(config);
        assert_eq!(stopper.best_loss(), f64::MAX);
        assert_eq!(stopper.counter(), 0);
    }

    #[test]
    fn test_reset() {
        let config = EarlyStoppingConfig {
            patience: 3,
            min_delta: 0.01,
        };
        let mut stopper = EarlyStopping::new(config);

        stopper.should_stop(1.0);
        stopper.should_stop(1.0);
        assert_eq!(stopper.counter(), 1);

        stopper.reset();
        assert_eq!(stopper.best_loss(), f64::MAX);
        assert_eq!(stopper.counter(), 0);
    }
}
