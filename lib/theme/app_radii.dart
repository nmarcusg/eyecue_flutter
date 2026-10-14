/// Corner-radius scale for EyeCue.
///
/// Values are extracted verbatim from existing `BorderRadius`/`Radius`
/// usage across the UI so this refactor does not change rendered output.
/// Prefer these tokens over raw `BorderRadius`/`Radius` literals in new UI.
/// Small radius — detection-box label pill corners.
const double kRadius4 = 4;

/// Small radius — priority badge corners.
const double kRadius6 = 6;

/// Small radius — debug overlay panel corners.
const double kRadius8 = 8;

/// Medium radius — cards, banners, summary containers.
const double kRadius12 = 12;

/// Medium radius — home status card.
const double kRadius16 = 16;

/// Large radius — status pill / gesture pill.
const double kRadius20 = 20;

/// Small radius — cyan rail accent (Home).
const double kRadius3 = 3;

/// Medium radius — Home-local CTA/toggle-like rounded treatment if a wrapper is needed.
const double kRadius14 = 14;

/// Medium radius — compact status treatment if required by the final composition.
const double kRadius18 = 18;

/// Large radius — large status badge and large Home surfaces.
const double kRadius24 = 24;
