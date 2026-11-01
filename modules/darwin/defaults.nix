{ config, pkgs, lib, ... }:

{
  # Applies to every Darwin homeConfiguration, including work-mac.
  targets.darwin.defaults.NSGlobalDomain = {
    # Current preferred values discovered with:
    #   defaults read -g KeyRepeat
    #   defaults read -g InitialKeyRepeat
    KeyRepeat = 2;
    InitialKeyRepeat = 10;

    # Make held letter keys repeat too, instead of showing the accent picker.
    ApplePressAndHoldEnabled = false;
  };

  # Apple Dictation stays off: its F5/Dictation key and sound are replaced by
  # the Transcription menu bar controller (record-mic | transcribe --tmp).
  targets.darwin.defaults."com.apple.assistant.support" = {
    "Dictation Enabled" = false;
  };
  targets.darwin.defaults."com.apple.HIToolbox" = {
    AppleDictationAutoEnable = false;
  };

  # Disabling Dictation alone leaves its hardware key opening an enable prompt.
  # Remap Consumer Voice Command (0x0C/0xCF) to keyboard F5 (0x07/0x3E)
  # before macOS interprets it. External F5 and Fn+F5 already emit F5.
  launchd.agents.transcription-key = {
    enable = true;
    config = {
      Label = "com.jack.transcription-key";
      ProgramArguments = [
        "/usr/bin/hidutil" "property" "--set"
        ''{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":51539607759,"HIDKeyboardModifierMappingDst":30064771134}]}''
      ];
      RunAtLoad = true;
    };
  };
}
