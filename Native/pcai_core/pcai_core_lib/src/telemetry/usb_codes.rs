use std::collections::HashMap;
use std::sync::OnceLock;

pub struct CmProblemInfo {
    pub code: u32,
    pub short_description: &'static str,
    pub help_summary: &'static str,
    pub help_url: &'static str,
}

static PROBLEM_MAP: OnceLock<HashMap<u32, CmProblemInfo>> = OnceLock::new();

pub fn get_problem_info(code: u32) -> Option<&'static CmProblemInfo> {
    let map = PROBLEM_MAP.get_or_init(|| {
        let mut m = HashMap::new();

        m.insert(1, CmProblemInfo {
            code: 1,
            short_description: "CM_PROB_NOT_CONFIGURED",
            help_summary: "The device is not configured correctly.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-not-configured",
        });

        m.insert(10, CmProblemInfo {
            code: 10,
            short_description: "CM_PROB_FAILED_START",
            help_summary: "The device cannot start. Try updating the drivers.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-failed-start",
        });

        m.insert(12, CmProblemInfo {
            code: 12,
            short_description: "CM_PROB_CONFLICTING_RESOURCES",
            help_summary: "The device cannot find enough free resources that it can use. If you want to use this device, you will need to disable one of the other devices on this system.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-conflicting-resources",
        });

        m.insert(14, CmProblemInfo {
            code: 14,
            short_description: "CM_PROB_NEED_RESTART",
            help_summary: "This device cannot work properly until you restart your computer.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-need-restart",
        });

        m.insert(18, CmProblemInfo {
            code: 18,
            short_description: "CM_PROB_REINSTALL",
            help_summary: "The drivers for this device need to be reinstalled.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-reinstall",
        });

        m.insert(19, CmProblemInfo {
            code: 19,
            short_description: "CM_PROB_REGISTRY_BAD",
            help_summary: "Windows cannot start this hardware device because its configuration information (in the registry) is incomplete or damaged.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-registry-bad",
        });

        m.insert(21, CmProblemInfo {
            code: 21,
            short_description: "CM_PROB_WILL_BE_REMOVED",
            help_summary: "Windows is removing this device.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-will-be-removed",
        });

        m.insert(22, CmProblemInfo {
            code: 22,
            short_description: "CM_PROB_DISABLED",
            help_summary: "The device is disabled in Device Manager.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-disabled",
        });

        m.insert(24, CmProblemInfo {
            code: 24,
            short_description: "CM_PROB_DEVICE_NOT_THERE",
            help_summary: "This device is not present, is not working properly, or does not have all its drivers installed.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-device-not-there",
        });

        m.insert(28, CmProblemInfo {
            code: 28,
            short_description: "CM_PROB_FAILED_INSTALL",
            help_summary: "The drivers for this device are not installed.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-failed-install",
        });

        m.insert(29, CmProblemInfo {
            code: 29,
            short_description: "CM_PROB_HARDWARE_DISABLED",
            help_summary: "This device is disabled because the firmware of the device did not give it the required resources.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-hardware-disabled",
        });

        m.insert(31, CmProblemInfo {
            code: 31,
            short_description: "CM_PROB_FAILED_ADD",
            help_summary: "This device is not working properly because Windows cannot load the drivers required for this device.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-failed-add",
        });

        m.insert(32, CmProblemInfo {
            code: 32,
            short_description: "CM_PROB_REGISTRY_QUARANTINE",
            help_summary: "A driver for this device has been disabled. An alternate driver may be providing this functionality.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-registry-quarantine",
        });

        m.insert(34, CmProblemInfo {
            code: 34,
            short_description: "CM_PROB_FAILED_CONFIG",
            help_summary: "Windows cannot determine the settings for this device. Consult the documentation that came with this device and use the Resource tab to set the configuration.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-failed-config",
        });

        m.insert(37, CmProblemInfo {
            code: 37,
            short_description: "CM_PROB_FAILED_DRIVER_ENTRY",
            help_summary: "Windows cannot initialize the device driver for this hardware.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-failed-driver-entry",
        });

        m.insert(38, CmProblemInfo {
            code: 38,
            short_description: "CM_PROB_DRIVER_FAILED_PRIOR_UNLOAD",
            help_summary: "Windows cannot load the device driver for this hardware because a previous instance of the device driver is still in memory.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-driver-failed-prior-unload",
        });

        m.insert(39, CmProblemInfo {
            code: 39,
            short_description: "CM_PROB_DRIVER_FAILED_LOAD",
            help_summary: "Windows cannot load the device driver for this hardware. The driver may be corrupted or missing.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-driver-failed-load",
        });

        m.insert(43, CmProblemInfo {
            code: 43,
            short_description: "CM_PROB_DEVICE_REPORTED_FAILURE",
            help_summary: "Windows has stopped this device because it has reported problems.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-device-reported-failure",
        });

        m.insert(45, CmProblemInfo {
            code: 45,
            short_description: "CM_PROB_NOT_CONNECTED",
            help_summary: "Currently, this hardware device is not connected to the computer. To fix this problem, reconnect this hardware device to the computer.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-not-connected",
        });

        m.insert(47, CmProblemInfo {
            code: 47,
            short_description: "CM_PROB_WILL_BE_REMOVED",
            help_summary: "Windows cannot use this hardware device because it has been prepared for safe removal, but it has not been removed from the computer.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-will-be-removed",
        });

        m.insert(48, CmProblemInfo {
            code: 48,
            short_description: "CM_PROB_DISABLED_SERVICE",
            help_summary: "The software for this device has been blocked from starting because it is known to have problems with Windows. Contact the hardware vendor for a new driver.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-disabled-service",
        });

        m.insert(52, CmProblemInfo {
            code: 52,
            short_description: "CM_PROB_UNSIGNED_DRIVER",
            help_summary: "Windows cannot verify the digital signature for the drivers required for this device. A recent hardware or software change might have installed a file that is signed incorrectly or damaged, or that might be malicious software from an unknown source.",
            help_url: "https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-unsigned-driver",
        });

        m
    });

    map.get(&code)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_problem_info_valid() {
        let info = get_problem_info(43).expect("Should find code 43");
        assert_eq!(info.short_description, "CM_PROB_DEVICE_REPORTED_FAILURE");
        assert!(info.help_summary.contains("reported problems"));
    }

    #[test]
    fn test_get_problem_info_invalid() {
        let info = get_problem_info(9999);
        assert!(info.is_none());
    }

    #[test]
    fn test_get_problem_info_disabled() {
        let info = get_problem_info(22).expect("Should find code 22");
        assert_eq!(info.short_description, "CM_PROB_DISABLED");
    }
}
