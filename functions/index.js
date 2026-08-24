const { initializeApp } = require("firebase-admin/app");
const { getDatabase } = require("firebase-admin/database");
const { onValueWritten } = require("firebase-functions/v2/database");

initializeApp();

const MINIMUM_DURATION_SECONDS = 60;
const MAXIMUM_DURATION_SECONDS = 8 * 60 * 60;
const OUTLIER_MINIMUM_SAMPLES = 4;

function normalizeStation(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/\b(station|metro)\b/g, "")
    .replace(/محطة/g, "")
    .replace(/[\u064B-\u065F\u0670]/g, "")
    .replace(/[^a-z0-9\u0621-\u064A]+/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function numberValue(value) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.round(number) : 0;
}

function nonEmpty(value) {
  const text = String(value || "").trim();
  return text && text !== "-" && text !== "—" ? text : null;
}

function orderedSegments(value) {
  if (!value || typeof value !== "object") return [];
  return Object.values(value)
    .filter((segment) => segment && typeof segment === "object")
    .sort((a, b) => numberValue(a.startedAt) - numberValue(b.startedAt));
}

function completedMetroTrip(trip) {
  if (!trip || String(trip.mode || "").toLowerCase() !== "metro") return null;
  if (String(trip.status || "").toLowerCase().includes("cancel")) return null;

  const startedAt = numberValue(trip.startedAt);
  const finishedAt = numberValue(trip.finishedAt);
  const elapsed = Math.floor((finishedAt - startedAt) / 1000);
  if (finishedAt <= startedAt || elapsed < MINIMUM_DURATION_SECONDS ||
      elapsed > MAXIMUM_DURATION_SECONDS) return null;

  const stored = numberValue(trip.durationSeconds);
  const durationSeconds = stored >= MINIMUM_DURATION_SECONDS &&
      stored <= MAXIMUM_DURATION_SECONDS &&
      Math.abs(elapsed - stored) <= (stored > 600 ? stored / 2 : 300)
    ? stored : elapsed;
  const segments = orderedSegments(trip.metroSegments);
  const from = nonEmpty(trip.fromStation) ||
    (segments.length ? nonEmpty(segments[0].fromStation || segments[0].from) : null);
  const to = nonEmpty(trip.toStation) ||
    (segments.length ? nonEmpty(segments.at(-1).toStation || segments.at(-1).to) : null);
  const fromKey = normalizeStation(from);
  const toKey = normalizeStation(to);
  if (!fromKey || !toKey) return null;

  const rawLines = Array.isArray(trip.metroLineKeys) && trip.metroLineKeys.length
    ? trip.metroLineKeys
    : segments.map((segment) => segment.lineKey);
  const lines = [...new Set(rawLines.map((line) => String(line || "").trim()).filter(Boolean))];
  return {
    routeKey: `${fromKey}__${toKey}`,
    durationSeconds,
    lines,
    transferCount: Math.max(0, lines.length - 1),
    finishedAt,
  };
}

exports.aggregateCompletedMetroTrip = onValueWritten(
  "/App/TravelHistory/{uid}/{tripId}",
  async (event) => {
    const trip = completedMetroTrip(event.data.after.val());
    if (!trip) return;

    const contributionId = `${event.params.uid}_${event.params.tripId}`;
    const internalRef = getDatabase().ref(
      `App/RouteAnalyticsInternal/metro/${trip.routeKey}`,
    );
    await internalRef.transaction((current) => {
      const stats = current && typeof current === "object" ? current : {};
      const processed = stats.processedTrips || {};
      if (processed[contributionId]) return;

      const sampleCount = numberValue(stats.sampleCount);
      const total = numberValue(stats.totalDurationSeconds);
      const average = sampleCount ? total / sampleCount : 0;
      const outlier = sampleCount >= OUTLIER_MINIMUM_SAMPLES &&
        (trip.durationSeconds < average * 0.5 || trip.durationSeconds > average * 2);

      // Idempotency data is private, so retrying a database event cannot add
      // the same completed trip to an aggregate more than once.
      processed[contributionId] = { processedAt: Date.now(), accepted: !outlier };
      stats.processedTrips = processed;
      if (outlier) {
        stats.rejectedOutlierCount = numberValue(stats.rejectedOutlierCount) + 1;
        return stats;
      }

      stats.sampleCount = sampleCount + 1;
      stats.totalDurationSeconds = total + trip.durationSeconds;
      stats.minimumDurationSeconds = sampleCount
        ? Math.min(numberValue(stats.minimumDurationSeconds), trip.durationSeconds)
        : trip.durationSeconds;
      stats.maximumDurationSeconds = Math.max(numberValue(stats.maximumDurationSeconds), trip.durationSeconds);
      stats.transferTotal = numberValue(stats.transferTotal) + trip.transferCount;
      stats.lineCounts = stats.lineCounts || {};
      trip.lines.forEach((line) => {
        stats.lineCounts[line] = numberValue(stats.lineCounts[line]) + 1;
      });
      stats.updatedAt = trip.finishedAt;
      return stats;
    });
  },
);

// The mobile app never receives raw trip identifiers or rejected samples.
exports.publishMetroRouteAnalytics = onValueWritten(
  "/App/RouteAnalyticsInternal/metro/{routeKey}",
  async (event) => {
    const stats = event.data.after.val();
    const publicRef = getDatabase().ref(
      `App/RouteAnalytics/metro/${event.params.routeKey}`,
    );
    if (!stats) return publicRef.remove();
    return publicRef.set({
      sampleCount: numberValue(stats.sampleCount),
      totalDurationSeconds: numberValue(stats.totalDurationSeconds),
      minimumDurationSeconds: numberValue(stats.minimumDurationSeconds),
      maximumDurationSeconds: numberValue(stats.maximumDurationSeconds),
      transferTotal: numberValue(stats.transferTotal),
      lineCounts: stats.lineCounts || {},
      updatedAt: numberValue(stats.updatedAt),
    });
  },
);
