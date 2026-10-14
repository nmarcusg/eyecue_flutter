/// Spacing scale for EyeCue.
///
/// Values are extracted verbatim from existing `EdgeInsets`/`SizedBox`
/// usage across the UI so this refactor does not change rendered output.
/// Prefer these tokens over raw `EdgeInsets`/`SizedBox` literals in new UI.
/// 1 logical pixel — hairline gaps between tightly stacked rows.
const double kSpace1 = 1;

/// 2 logical pixels — small gaps between compact rows.
const double kSpace2 = 2;

/// 3 logical pixels — vertical rhythm inside compact metric rows.
const double kSpace3 = 3;

/// 4 logical pixels — small vertical gaps between related elements.
const double kSpace4 = 4;

/// 6 logical pixels — small gaps between inline elements.
const double kSpace6 = 6;

/// 8 logical pixels — standard small gap between stacked elements.
const double kSpace8 = 8;

/// 10 logical pixels — medium gap between related blocks.
const double kSpace10 = 10;

/// 12 logical pixels — standard gap between related blocks.
const double kSpace12 = 12;

/// 14 logical pixels — comfortable padding for cards/containers.
const double kSpace14 = 14;

/// 16 logical pixels — standard screen/card padding.
const double kSpace16 = 16;

/// 18 logical pixels — comfortable button horizontal padding.
const double kSpace18 = 18;

/// 20 logical pixels — large gap between major blocks.
const double kSpace20 = 20;

/// 24 logical pixels — primary screen padding / large section gap.
const double kSpace24 = 24;

/// 32 logical pixels — extra-large section gap.
const double kSpace32 = 32;

/// 180 logical pixels — fixed chart height in Logs & Reports.
const double kChartHeight = 180;

/// Minimum touch target width for accessible controls (48dp+ guidance).
const double kMinTouchWidth = 64;

/// Minimum touch target height for accessible controls (48dp+ guidance).
const double kMinTouchHeight = 56;
