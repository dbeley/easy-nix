/*
  Browsers: Firefox and Chromium.

  Firefox is configured by policy rather than by a profile shipped in the image, so
  the settings cannot drift from the file and are visible with `about:policies`.

  Chromium is `ungoogled-chromium`: the same engine without the Google service
  integration. The trade-offs are real and documented in the README (no Widevine, so
  no DRM streaming; no Google account sync).
*/
{
  pkgs,
  ...
}:
{
  programs.firefox = {
    enable = true;
    # The system owns updates; Mozilla's own updater cannot reach into /nix/store and
    # a browser that tries to update itself only creates confusion.
    policies = {
      DisableAppUpdate = true;
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DisableFirefoxAccounts = true;
      DisablePocket = true;
      DisableFeedbackCommands = true;
      DontCheckDefaultBrowser = true;
      NoDefaultBookmarks = true;
      OfferToSaveLogins = false;
      ShowHomeButton = true;
      EnableTrackingProtection = {
        Value = true;
        Locked = true;
        Cryptomining = true;
        Fingerprinting = true;
      };
      # The bookmark sync extension is not installed: an appliance that phones home
      # is not an appliance.
      ExtensionSettings = { };
    };

    # Keep the profile keys of a browser that has no profile management UI worth the
    # name, and make sure the search engine is not a data broker.
    preferences = {
      "browser.startup.homepage" = "about:blank";
      "browser.newtabpage.enabled" = false;
      "browser.search.suggest.enabled" = false;
      "datareporting.policy.dataSubmissionEnabled" = false;
      "toolkit.telemetry.enabled" = false;
      "extensions.pocket.enabled" = false;
    };
  };

  environment.systemPackages = with pkgs; [
    ungoogled-chromium
  ];
}
