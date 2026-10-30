/// Corner-radius scale for EyeCue.
///
/// Values are extracted verbatim from existing `BorderRadius`/`Radius`
/// usage across the UI so this refactor does not change rendered output.
/// Prefer these tokens over raw `BorderRadius`/`Radius` literals in new UI.
/// Small radius — priority badge corners.
const double kRadius6 = 6;

/// Medium radius — cards, banners, summary containers.
const double kRadius12 = 12;

/// Large radius — status pill / gesture pill.
const double kRadius20 = 20;

/// Small radius — cyan rail accent (Home).
const double kRadius3 = 3;

/// Medium radius — Home-local CTA/toggle-like rounded treatment if a wrapper is needed.
const double kRadius14 = 14;

/// Large radius — large status badge and large Home surfaces.
const double kRadius24 = 24;
