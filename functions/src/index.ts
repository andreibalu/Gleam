/**
 * Firebase Cloud Functions for Gleam
 * Dental analysis powered by OpenAI GPT-4o-mini
 */

import {createHash} from "crypto";
import {setGlobalOptions} from "firebase-functions";
import {onRequest} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import OpenAI from "openai";
import * as logger from "firebase-functions/logger";

// Initialize Firebase Admin
admin.initializeApp();

// For cost control, limit concurrent instances
setGlobalOptions({
  maxInstances: 10,
  secrets: ["OPENAI_API_KEY"],
});

// Initialize OpenAI client
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY || "",
});

const DEFAULT_PLAN: Recommendations = {
  immediate: [
    "Brush with whitening toothpaste tonight",
    "Rinse with water after dark drinks",
    "Floss gently before bed",
  ],
  daily: [
    "Use an electric toothbrush each morning",
    "Swish a fluoride mouthwash before sleep",
  ],
  weekly: [
    "Apply gentle whitening strips once",
    "Polish with a soft whitening pen",
  ],
  caution: [
    "Skip dark sodas for 48 hours",
    "Limit coffee to one cup before noon",
  ],
};

interface DetectedIssue {
  key: string;
  severity: string;
  notes: string;
}

interface Recommendations {
  immediate: string[];
  daily: string[];
  weekly: string[];
  caution: string[];
}

interface ScanResult {
  whitenessScore: number;
  shade: string;
  detectedIssues: DetectedIssue[];
  confidence: number;
  referralNeeded: boolean;
  disclaimer: string;
  personalTakeaway: string;
}

interface AnalyzeResponse {
  id?: string;
  result: ScanResult;
  contextTags?: string[];
  createdAt?: FirebaseFirestore.Timestamp;
  streak?: StreakSnapshot;
}

interface PlanHistorySnapshot {
  capturedAt: string;
  whitenessScore: number;
  shade: string;
  detectedIssues: DetectedIssue[];
  lifestyleTags: string[];
  personalTakeaway: string;
}

interface PlanResponseMetadata {
  source: "default" | "latest-cache" | "openai";
  unchanged: boolean;
  reason?:
    | "missing-history"
    | "history-identical"
    | "latest-request"
    | "insufficient-scans"
    | "awaiting-refresh";
  inputHash?: string;
  updatedAt?: string;
  totalScans?: number;
  scansUntilNextPlan?: number;
  scansSinceLastPlan?: number;
  latestPlanScanCount?: number;
  planAvailable?: boolean;
  nextPlanAtScanCount?: number;
  refreshInterval?: number;
}

interface PlanResponsePayload {
  plan: Recommendations;
  meta?: PlanResponseMetadata;
}

interface LatestPlanDocument {
  latestPlan?: Recommendations;
  latestPlanInputHash?: string;
  latestPlanUpdatedAt?: FirebaseFirestore.Timestamp;
  latestPlanScanCount?: number;
  totalScanCount?: number;
}

interface StreakSnapshot {
  current: number;
  best: number;
  lastScanDate?: string;
}

const LIFESTYLE_TAG_LABELS: Record<string, string> = {
  coffee: "coffee",
  red_wine: "red wine",
  cola: "cola & soda",
  tea: "tea",
  smoking: "smoking",
};

const PROMPT_KEYWORD_TO_TAG_ID: Record<string, string> = {
  "coffee": "coffee",
  "red wine": "red_wine",
  "sugary dark soda": "cola",
  "dark tea": "tea",
  "tobacco smoke": "smoking",
};

const PLAN_CONTEXT_SCAN_LIMIT = 10;
const PLAN_REFRESH_INTERVAL = 10;
const PLAN_MIN_SCANS_FOR_PERSONALIZED_PLAN = 10;

const TAG_ID_TO_PROMPT_KEYWORD: Record<string, string> =
  Object.entries(PROMPT_KEYWORD_TO_TAG_ID).reduce(
    (accumulator, [keyword, tagId]) => {
      if (!accumulator[tagId]) {
        accumulator[tagId] = keyword;
      }
      return accumulator;
    },
    {} as Record<string, string>
  );

/**
 * Error representing an authentication failure.
 */
class UnauthorizedError extends Error {
  /**
   * Creates an UnauthorizedError.
   * @param {string} message - Optional override message.
   */
  constructor(message = "Unauthorized") {
    super(message);
    this.name = "UnauthorizedError";
  }
}

/**
 * Verifies the Firebase ID token in the request and returns the uid.
 * @param {Object} req - The incoming HTTP request.
 * @return {Promise<string>} The verified user's uid.
 * @throws {UnauthorizedError} When verification fails.
 */
async function requireUid(req: {
  headers: {[key: string]: string | string[] | undefined};
}): Promise<string> {
  const authorization = req.headers.authorization ||
    req.headers.Authorization ||
    "";
  const token =
    typeof authorization === "string" ?
      authorization.trim() :
      Array.isArray(authorization) ?
        authorization[0]?.trim() :
        "";

  const match = token.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    throw new UnauthorizedError("Missing bearer token");
  }

  try {
    const decoded = await admin.auth().verifyIdToken(match[1]);
    if (!decoded?.uid) {
      throw new UnauthorizedError("Invalid token");
    }
    return decoded.uid;
  } catch (error) {
    throw new UnauthorizedError("Failed to verify token");
  }
}

/**
 * Returns a human-friendly label for a lifestyle tag id.
 * @param {string} tagId - Lifestyle tag identifier.
 * @return {string} Friendly label.
 */
function friendlyLabelForTagId(tagId: string): string {
  return LIFESTYLE_TAG_LABELS[tagId] ?? tagId;
}

/**
 * Maps a prompt keyword back to its canonical lifestyle tag id.
 * @param {string} keyword - Prompt keyword provided by the client.
 * @return {string | null} Canonical tag id or null if unknown.
 */
function tagIdFromPromptKeyword(keyword: string): string | null {
  return PROMPT_KEYWORD_TO_TAG_ID[keyword] ?? null;
}

/**
 * Maps a lifestyle tag id to its canonical prompt keyword.
 * @param {string} tagId - Lifestyle tag identifier.
 * @return {string | null} Prompt keyword or null if unknown.
 */
function promptKeywordForTagId(tagId: string): string | null {
  return TAG_ID_TO_PROMPT_KEYWORD[tagId] ?? null;
}

const KNOWN_LIFESTYLE_TAG_IDS = Object.keys(LIFESTYLE_TAG_LABELS);
const MS_IN_DAY = 24 * 60 * 60 * 1000;

/**
 * Produces the UTC start-of-day date for the provided date.
 * @param {Date} date - Date to normalize.
 * @return {Date} Normalized date at 00:00 UTC.
 */
function startOfUtcDay(date: Date): Date {
  return new Date(Date.UTC(
    date.getUTCFullYear(),
    date.getUTCMonth(),
    date.getUTCDate()
  ));
}

/**
 * Returns the day difference between two dates using UTC day boundaries.
 * @param {Date} later - Later date.
 * @param {Date} earlier - Earlier date.
 * @return {number} Difference in full days.
 */
function daysBetween(later: Date, earlier: Date): number {
  const laterDay = startOfUtcDay(later).getTime();
  const earlierDay = startOfUtcDay(earlier).getTime();
  return Math.round((laterDay - earlierDay) / MS_IN_DAY);
}

/**
 * Updates and returns the user's streak snapshot.
 * @param {string} uid - Firebase auth user id.
 * @param {FirebaseFirestore.Timestamp} scanTimestamp - Timestamp for the scan.
 * @return {Promise<StreakSnapshot>} Updated streak snapshot.
 */
async function updateUserStreak(
  uid: string,
  scanTimestamp: FirebaseFirestore.Timestamp
): Promise<StreakSnapshot> {
  const userRef = admin.firestore().collection("users").doc(uid);
  return admin.firestore().runTransaction(async (tx) => {
    const snapshot = await tx.get(userRef);
    const data = snapshot.exists ? snapshot.data() as {
      currentStreak?: number;
      bestStreak?: number;
      lastScanDate?: FirebaseFirestore.Timestamp;
      totalScanCount?: number;
    } : {};

    const previousStreak = typeof data?.currentStreak === "number" ?
      data.currentStreak :
      0;
    const bestStreak = typeof data?.bestStreak === "number" ?
      data.bestStreak :
      0;
    const lastScanTimestamp = data?.lastScanDate;
    const previousTotalScanCount = typeof data?.totalScanCount === "number" ?
      data.totalScanCount :
      0;

    const scanDate = scanTimestamp.toDate();
    const scanDay = startOfUtcDay(scanDate);

    let newCurrent = 1;
    if (lastScanTimestamp) {
      const lastDay = startOfUtcDay(lastScanTimestamp.toDate());
      const diff = daysBetween(scanDay, lastDay);
      if (diff === 0) {
        newCurrent = Math.max(previousStreak, 1);
      } else if (diff === 1) {
        newCurrent = previousStreak + 1;
      } else if (diff > 1) {
        newCurrent = 1;
      } else if (diff < 0) {
        newCurrent = previousStreak;
      }
    }

    const newBest = Math.max(bestStreak, newCurrent);
    const newTotalScanCount = previousTotalScanCount + 1;
    tx.set(userRef, {
      currentStreak: newCurrent,
      bestStreak: newBest,
      lastScanDate: scanTimestamp,
      streakUpdatedAt: admin.firestore.Timestamp.now(),
      totalScanCount: newTotalScanCount,
    }, {merge: true});

    return {
      current: newCurrent,
      best: newBest,
      lastScanDate: scanDay.toISOString(),
    };
  });
}

/**
 * Stores the latest personalized plan metadata for the user.
 * @param {string} uid - Firebase auth user id.
 * @param {Recommendations} plan - Latest recommendations.
 * @param {string} inputHash - Hash representing the plan input context.
 * @param {FirebaseFirestore.Timestamp} updatedAt - Timestamp for freshness.
 * @param {number} scanCountAtGeneration - Total scans at time of generation.
 * @return {Promise<void>} Promise that resolves when metadata is saved.
 */
async function setLatestPlan(
  uid: string,
  plan: Recommendations,
  inputHash: string,
  updatedAt: FirebaseFirestore.Timestamp,
  scanCountAtGeneration: number
): Promise<void> {
  await admin.firestore().collection("users").doc(uid).set({
    latestPlan: plan,
    latestPlanInputHash: inputHash,
    latestPlanUpdatedAt: updatedAt,
    latestPlanScanCount: scanCountAtGeneration,
  }, {merge: true});
}

/**
 * Removes legacy plan cache documents stored under users/{uid}/plans.
 * This is a no-op when the collection is already empty.
 * @param {string} uid - Firebase auth user id.
 * @return {Promise<void>} Promise that resolves when cleanup attempts finish.
 */
async function clearLegacyPlanCache(uid: string): Promise<void> {
  try {
    const plansCollection = admin.firestore()
      .collection("users")
      .doc(uid)
      .collection("plans");

    const legacyDocRefs = await plansCollection.listDocuments();
    if (legacyDocRefs.length === 0) {
      return;
    }

    const results = await Promise.allSettled(
      legacyDocRefs.map((docRef) => docRef.delete())
    );

    results.forEach((result, index) => {
      if (result.status === "rejected") {
        logger.warn("Failed to delete legacy plan cache entry", {
          uid,
          planId: legacyDocRefs[index].id,
          error: result.reason instanceof Error ?
            result.reason.message :
            result.reason,
        });
      }
    });
  } catch (error) {
    logger.warn("Failed to clear legacy plan cache", {
      uid,
      error: error instanceof Error ? error.message : error,
    });
  }
}

/**
 * Analyze endpoint: receives base64 image, returns dental analysis
 */
export const analyze = onRequest(
  {cors: true, maxInstances: 5},
  async (req, res) => {
    // Enforce POST method only
    if (req.method !== "POST") {
      res.status(405).json({error: "Method Not Allowed"});
      return;
    }

    let uid: string;
    try {
      uid = await requireUid(req);
    } catch (error) {
      logger.warn(
        "Unauthorized analyze request",
        {error: error instanceof Error ? error.message : error}
      );
      res.status(401).json({error: "Unauthorized"});
      return;
    }

    try {
      const {
        image,
        tags: rawTags,
        previousTakeaways: rawPreviousTakeaways,
        tagHistory: rawTagHistory,
      } = req.body as {
        image?: string;
        tags?: unknown;
        previousTakeaways?: unknown;
        tagHistory?: unknown;
      };

      if (!image || typeof image !== "string") {
        res.status(400).json({error: "Missing or invalid 'image' field"});
        return;
      }

      const tags = Array.isArray(rawTags) ?
        Array.from(
          new Set(
            (rawTags as unknown[])
              .filter((tag): tag is string =>
                typeof tag === "string" && tag.trim().length > 0)
              .map((tag) => tag.trim())
          )
        ) :
        [];

      const previousTakeaways =
        Array.isArray(rawPreviousTakeaways) ?
          (rawPreviousTakeaways as unknown[])
            .filter((entry): entry is string =>
              typeof entry === "string" &&
                entry.trim().length > 0)
            .slice(0, 5) :
          [];

      const tagHistory =
        Array.isArray(rawTagHistory) ?
          (rawTagHistory as unknown[])
            .slice(0, 5)
            .map((entry) => {
              if (!Array.isArray(entry)) {
                return [];
              }
              return (entry as unknown[])
                .map((tag) =>
                  typeof tag === "string" ? tag.trim() : ""
                )
                .filter((tag) => tag.length > 0);
            }) :
          [];

      const uniqueTagHistory = tagHistory.map((entry) =>
        Array.from(new Set(entry))
      );

      const currentTagIds = Array.from(
        new Set(
          tags
            .map((tag) =>
              tagIdFromPromptKeyword(tag.toLowerCase()))
            .filter((tagId): tagId is string => !!tagId)
        )
      );

      const currentTagLabels = currentTagIds.map((tagId) =>
        friendlyLabelForTagId(tagId)
      );

      const previousTagIds =
        uniqueTagHistory.length > 0 ? uniqueTagHistory[0] : [];
      const previousTagLabels = previousTagIds.map((tagId) =>
        friendlyLabelForTagId(tagId)
      );

      const tagUsageCounts = KNOWN_LIFESTYLE_TAG_IDS.reduce(
        (accumulator, tagId) => {
          accumulator[tagId] = 0;
          return accumulator;
        },
        {} as Record<string, number>
      );

      uniqueTagHistory.forEach((entry) => {
        const seen = new Set(entry);
        seen.forEach((tagId) => {
          if (tagUsageCounts[tagId] !== undefined) {
            tagUsageCounts[tagId] += 1;
          }
        });
      });

      const totalTagSamples = uniqueTagHistory.length;

      const formatList = (items: string[], fallback = "none"): string =>
        items.length > 0 ? items.join(", ") : fallback;

      const newTagIds = currentTagIds.filter(
        (id) => !previousTagIds.includes(id)
      );
      const droppedTagIds = previousTagIds.filter(
        (id) => !currentTagIds.includes(id)
      );

      const newTagLabels = newTagIds.map((tagId) =>
        friendlyLabelForTagId(tagId)
      );
      const droppedTagLabels = droppedTagIds.map((tagId) =>
        friendlyLabelForTagId(tagId)
      );

      const frequentTagSummary = totalTagSamples > 0 ?
        KNOWN_LIFESTYLE_TAG_IDS
          .map((tagId) => ({
            tagId,
            count: tagUsageCounts[tagId] ?? 0,
          }))
          .filter(({count}) => count > 0)
          .sort((a, b) => b.count - a.count)
          .slice(0, 2)
          .map(({tagId, count}) =>
            `${friendlyLabelForTagId(tagId)} ${count}/${totalTagSamples}`)
          .join(", ") :
        "";

      const avoidedTagLabels = totalTagSamples > 0 ?
        KNOWN_LIFESTYLE_TAG_IDS
          .filter((tagId) => (tagUsageCounts[tagId] ?? 0) === 0)
          .map((tagId) => friendlyLabelForTagId(tagId))
          .slice(0, 2) :
        [];

      const scanContextLines: string[] = [];
      scanContextLines.push(
        "Current lifestyle tags: " +
          `${formatList(currentTagLabels)}.`
      );

      if (previousTagIds.length > 0) {
        scanContextLines.push(
          "Previous scan tags: " +
            `${formatList(previousTagLabels)}.`
        );
      } else {
        scanContextLines.push(
          "No prior scans in streak; treat as baseline."
        );
      }

      if (newTagLabels.length > 0) {
        scanContextLines.push(
          "New this scan: " +
            `${formatList(newTagLabels)}. Coach the slip.`
        );
      }

      if (droppedTagLabels.length > 0) {
        scanContextLines.push(
          "Dropped since last scan: " +
            `${formatList(droppedTagLabels)}. Celebrate it.`
        );
      }

      if (frequentTagSummary.length > 0) {
        scanContextLines.push(
          "Frequent tags over " +
            `${totalTagSamples} scans: ${frequentTagSummary}.`
        );
      }

      if (avoidedTagLabels.length > 0) {
        scanContextLines.push(
          "Consistently avoided tags: " +
            `${formatList(avoidedTagLabels)}.`
        );
      }

      if (previousTakeaways.length > 0) {
        scanContextLines.push(
          "Avoid reusing takeaways: " +
            `${previousTakeaways.join(" | ")}.`
        );
      }

      const userText = [
        "Review the smile photo and return the JSON diagnosis.",
        ...scanContextLines,
      ].join("\n");

      const guidanceLines = [
        "- Provide a single Vita shade code (e.g., A2).",
        "- Compare tags to the previous scan; praise wins and coach new slips.",
        "- Keep personalTakeaway ≤ 12 words and reflect the real behavior.",
        "- Keep detectedIssues concise (notes ≤ 12 words).",
        "- Set referralNeeded true only for clinical escalation.",
        "- Keep the disclaimer under 18 words in plain language.",
        "- Confidence must stay between 0.0 and 1.0.",
      ].join("\n");

      logger.info("Processing dental scan analysis", {
        uid,
        tags,
        previousTakeawaysCount: previousTakeaways.length,
        tagHistorySamples: totalTagSamples,
      });

      // Call OpenAI GPT-4o-mini with vision
      const response = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content:
              "You are Gleam's virtual cosmetic dental designer. " +
              "Study each smile photo, evaluate whitening opportunities, " +
              `and deliver precise coaching in an uplifting tone.
Return ONLY valid JSON that matches this schema exactly:
{
  "whitenessScore": number (0-100),
  "shade": string,
  "detectedIssues": [
    {
      "key": string,
      "severity": "low" | "medium" | "high",
      "notes": string
    }
  ],
  "confidence": number (0.0-1.0),
  "referralNeeded": boolean,
  "disclaimer": string,
  "personalTakeaway": string
}
Guidance:
${guidanceLines}
`,
          },
          {
            role: "user",
            content: [
              {
                type: "text",
                text: userText,
              },
              {
                type: "image_url",
                image_url: {
                  url: `data:image/jpeg;base64,${image}`,
                },
              },
            ],
          },
        ],
        response_format: {type: "json_object"},
        temperature: 0.2,
        max_tokens: 320,
      });

      // Parse the result
      const content = response.choices[0].message.content;
      if (!content) {
        throw new Error("Empty response from OpenAI");
      }

      const result = JSON.parse(content) as ScanResult;

      logger.info("Analysis completed successfully", {
        uid,
        whitenessScore: result.whitenessScore,
        confidence: result.confidence,
      });

      const createdAt = admin.firestore.Timestamp.now();
      const record: AnalyzeResponse = {
        result,
        contextTags: currentTagIds,
        createdAt,
      };

      const scanDocRef = admin.firestore()
        .collection("users")
        .doc(uid)
        .collection("scanResults")
        .doc();

      await scanDocRef.set({
        id: scanDocRef.id,
        uid,
        ...record,
        promptKeywords: tags,
        createdAt,
      });

      const streak = await updateUserStreak(uid, createdAt);

      res.json({
        id: scanDocRef.id,
        result,
        contextTags: currentTagIds,
        createdAt: createdAt.toDate().toISOString(),
        streak,
      });
    } catch (error) {
      logger.error("Error analyzing image", error);

      if (error instanceof OpenAI.APIError) {
        res.status(error.status || 500).json({
          error: "OpenAI API error",
          message: error.message,
        });
      } else if (error instanceof SyntaxError) {
        res.status(500).json({
          error: "Invalid JSON response from AI",
          message: error.message,
        });
      } else {
        res.status(500).json({
          error: "Internal server error",
          message: error instanceof Error ? error.message : "Unknown error",
        });
      }
    }
  }
);

export const history = onRequest(
  {cors: true, maxInstances: 5},
  async (req, res) => {
    if (req.method === "DELETE") {
      let uid: string;
      try {
        uid = await requireUid(req);
      } catch (error) {
        logger.warn(
          "Unauthorized history delete request",
          {error: error instanceof Error ? error.message : error}
        );
        res.status(401).json({error: "Unauthorized"});
        return;
      }

      const body = req.body as {id?: unknown} | undefined;
      const queryId =
        typeof req.query?.id === "string" ? req.query.id : undefined;
      const requestedId = typeof body?.id === "string" ? body.id : queryId;

      if (!requestedId) {
        res.status(400).json({error: "Missing 'id' parameter"});
        return;
      }

      try {
        const userRef = admin.firestore().collection("users").doc(uid);
        const scanRef = userRef.collection("scanResults").doc(requestedId);
        const snapshot = await scanRef.get();
        if (!snapshot.exists) {
          res.status(404).json({error: "Scan not found"});
          return;
        }

        await scanRef.delete();
        await refreshUserScanCounters(uid);

        res.json({success: true});
      } catch (error) {
        logger.error("Failed to delete history item", {
          uid,
          scanId: requestedId,
          error: error instanceof Error ? error.message : error,
        });
        res.status(500).json({error: "Internal server error"});
      }
      return;
    }

    if (req.method !== "GET") {
      res.status(404).json({error: "Not Found"});
      return;
    }

    let uid: string;
    try {
      uid = await requireUid(req);
    } catch (error) {
      logger.warn(
        "Unauthorized history request",
        {error: error instanceof Error ? error.message : error}
      );
      res.status(401).json({error: "Unauthorized"});
      return;
    }

    const normalizedPath = (req.path || "").replace(/^\/+/, "");
    const isLatestRequest = normalizedPath === "latest";

    try {
      const historyRef = admin
        .firestore()
        .collection("users")
        .doc(uid)
        .collection("scanResults");

      if (isLatestRequest) {
        const snapshot = await historyRef
          .orderBy("createdAt", "desc")
          .limit(1)
          .get();

        if (snapshot.empty) {
          res.status(404).json({error: "No scans found"});
          return;
        }

        const data = snapshot.docs[0].data() as AnalyzeResponse & {
          createdAt?: FirebaseFirestore.Timestamp;
        };
        res.json({
          id: snapshot.docs[0].id,
          result: data.result,
          contextTags: data.contextTags ?? [],
          createdAt: data.createdAt ?
            data.createdAt.toDate().toISOString() :
            undefined,
        });
        return;
      }

      if (normalizedPath !== "" && normalizedPath !== "history") {
        res.status(404).json({error: "Not Found"});
        return;
      }

      const limitParam = req.query?.limit as string | undefined;
      const limitValue = Number(limitParam);
      const limit = Number.isFinite(limitValue) ?
        Math.min(100, Math.max(1, Math.floor(limitValue))) :
        25;

      const snapshot = await historyRef
        .orderBy("createdAt", "desc")
        .limit(limit)
        .get();

      const items = snapshot.docs.map((doc) => {
        const data = doc.data() as AnalyzeResponse & {
          createdAt?: FirebaseFirestore.Timestamp;
        };

        return {
          id: doc.id,
          result: data.result,
          contextTags: data.contextTags ?? [],
          createdAt: data.createdAt ?
            data.createdAt.toDate().toISOString() :
            null,
        };
      });

      res.json({items});
    } catch (error) {
      logger.error("Failed to load scan history", error);
      res.status(500).json({error: "Internal server error"});
    }
  }
);

export const plan = onRequest(
  {cors: true, maxInstances: 5},
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({error: "Method Not Allowed"});
      return;
    }

    let uid: string;
    try {
      uid = await requireUid(req);
    } catch (error) {
      logger.warn(
        "Unauthorized plan request",
        {error: error instanceof Error ? error.message : error}
      );
      res.status(401).json({error: "Unauthorized"});
      return;
    }

    try {
      const {userRef, userData, history, totalScanCount} =
        await loadPlanContext(uid);

      const latestPlan = userData.latestPlan;
      const latestPlanInputHash = userData.latestPlanInputHash;
      const latestPlanUpdatedAtIso = userData.latestPlanUpdatedAt ?
        userData.latestPlanUpdatedAt.toDate().toISOString() :
        undefined;
      const latestPlanScanCount =
        typeof userData.latestPlanScanCount === "number" ?
          userData.latestPlanScanCount :
          undefined;

      const scansSinceLastPlan = typeof latestPlanScanCount === "number" ?
        Math.max(totalScanCount - latestPlanScanCount, 0) :
        undefined;

      if (
        totalScanCount < PLAN_MIN_SCANS_FOR_PERSONALIZED_PLAN ||
        history.length === 0
      ) {
        const scansUntilFirstPlan = Math.max(
          PLAN_MIN_SCANS_FOR_PERSONALIZED_PLAN - totalScanCount,
          0
        );

        res.json({
          plan: DEFAULT_PLAN,
          meta: {
            source: "default",
            unchanged: false,
            reason: "insufficient-scans",
            totalScans: totalScanCount,
            scansUntilNextPlan: scansUntilFirstPlan,
            scansSinceLastPlan,
            latestPlanScanCount,
            planAvailable: false,
            nextPlanAtScanCount: PLAN_MIN_SCANS_FOR_PERSONALIZED_PLAN,
            refreshInterval: PLAN_REFRESH_INTERVAL,
          },
        });
        return;
      }

      const inputHash = computePlanHistoryHash(history);

      const shouldGenerate =
        !latestPlan ||
        typeof latestPlanScanCount !== "number" ||
        typeof scansSinceLastPlan !== "number" ||
        scansSinceLastPlan >= PLAN_REFRESH_INTERVAL;

      if (!shouldGenerate && latestPlan) {
        const scansUntilNextPlan = Math.max(
          PLAN_REFRESH_INTERVAL - scansSinceLastPlan,
          0
        );

        try {
          await userRef.set({
            latestPlanAccessedAt: admin.firestore.Timestamp.now(),
          }, {merge: true});
        } catch (error) {
          logger.debug("Failed to update latestPlanAccessedAt", {
            uid,
            error: error instanceof Error ? error.message : error,
          });
        }

        res.json({
          plan: latestPlan,
          meta: {
            source: "latest-cache",
            unchanged: true,
            reason: "awaiting-refresh",
            inputHash: latestPlanInputHash,
            updatedAt: latestPlanUpdatedAtIso,
            totalScans: totalScanCount,
            scansUntilNextPlan,
            scansSinceLastPlan,
            latestPlanScanCount,
            planAvailable: true,
            nextPlanAtScanCount: typeof latestPlanScanCount === "number" ?
              latestPlanScanCount + PLAN_REFRESH_INTERVAL :
              undefined,
            refreshInterval: PLAN_REFRESH_INTERVAL,
          },
        });
        return;
      }

      const {plan: generatedPlan, createdAt} =
        await generatePlanForUser(uid, history, totalScanCount, inputHash);

      res.json({
        plan: generatedPlan,
        meta: {
          source: "openai",
          unchanged: false,
          inputHash,
          updatedAt: createdAt.toDate().toISOString(),
          totalScans: totalScanCount,
          scansSinceLastPlan: 0,
          scansUntilNextPlan: PLAN_REFRESH_INTERVAL,
          latestPlanScanCount: totalScanCount,
          planAvailable: true,
          nextPlanAtScanCount: totalScanCount + PLAN_REFRESH_INTERVAL,
          refreshInterval: PLAN_REFRESH_INTERVAL,
        },
      });
    } catch (error) {
      logger.error("Error generating personalized plan", error);

      if (error instanceof OpenAI.APIError) {
        res.status(error.status || 500).json({
          error: "OpenAI API error",
          message: error.message,
        });
      } else if (error instanceof SyntaxError) {
        res.status(500).json({
          error: "Invalid JSON response from AI",
          message: error.message,
        });
      } else {
        res.status(500).json({
          error: "Internal server error",
          message: error instanceof Error ? error.message : "Unknown error",
        });
      }
    }
  }
);

export const planLatest = onRequest(
  {cors: true, maxInstances: 5},
  async (req, res) => {
    const isLatestRequest = req.path === "/latest" || req.path === "latest";
    if (req.method !== "GET" || !isLatestRequest) {
      res.status(404).json({error: "Not Found"});
      return;
    }

    let uid: string;
    try {
      uid = await requireUid(req);
    } catch (error) {
      logger.warn(
        "Unauthorized planLatest request",
        {error: error instanceof Error ? error.message : error}
      );
      res.status(401).json({error: "Unauthorized"});
      return;
    }

    try {
      const {
        userData,
        history,
        totalScanCount,
      } = await loadPlanContext(uid);

      let latestPlan = userData.latestPlan;
      let latestPlanInputHash = userData.latestPlanInputHash;
      let latestPlanScanCount =
        typeof userData.latestPlanScanCount === "number" ?
          userData.latestPlanScanCount :
          undefined;
      let latestPlanUpdatedAtIso = userData.latestPlanUpdatedAt ?
        userData.latestPlanUpdatedAt.toDate().toISOString() :
        undefined;

      let scansSinceLastPlan = typeof latestPlanScanCount === "number" ?
        Math.max(totalScanCount - latestPlanScanCount, 0) :
        undefined;

      if (
        totalScanCount < PLAN_MIN_SCANS_FOR_PERSONALIZED_PLAN ||
        history.length === 0
      ) {
        const scansUntilPlan = Math.max(
          PLAN_MIN_SCANS_FOR_PERSONALIZED_PLAN - totalScanCount,
          0
        );

        res.json({
          plan: latestPlan ?? DEFAULT_PLAN,
          meta: {
            source: latestPlan ? "latest-cache" : "default",
            unchanged: !!latestPlan,
            reason: "insufficient-scans",
            inputHash: latestPlanInputHash,
            updatedAt: latestPlanUpdatedAtIso,
            totalScans: totalScanCount,
            scansUntilNextPlan: scansUntilPlan,
            scansSinceLastPlan,
            latestPlanScanCount,
            planAvailable: false,
            nextPlanAtScanCount: PLAN_MIN_SCANS_FOR_PERSONALIZED_PLAN,
            refreshInterval: PLAN_REFRESH_INTERVAL,
          },
        });
        return;
      }

      const inputHash = computePlanHistoryHash(history);
      let didGenerate = false;
      const shouldGenerate =
        !latestPlan ||
        typeof latestPlanScanCount !== "number" ||
        typeof scansSinceLastPlan !== "number" ||
        scansSinceLastPlan >= PLAN_REFRESH_INTERVAL;

      if (shouldGenerate) {
        const {plan: generatedPlan, createdAt} =
          await generatePlanForUser(uid, history, totalScanCount, inputHash);
        latestPlan = generatedPlan;
        latestPlanInputHash = inputHash;
        latestPlanScanCount = totalScanCount;
        latestPlanUpdatedAtIso = createdAt.toDate().toISOString();
        scansSinceLastPlan = 0;
        didGenerate = true;
      }

      const planAvailable = !!latestPlan;
      const scansUntilNextPlan = planAvailable ?
        Math.max(
          PLAN_REFRESH_INTERVAL - (scansSinceLastPlan ?? 0),
          0
        ) :
        Math.max(
          PLAN_MIN_SCANS_FOR_PERSONALIZED_PLAN - totalScanCount,
          0
        );

      const metaSource: PlanResponseMetadata["source"] = didGenerate ?
        "openai" :
        "latest-cache";
      const metaReason = planAvailable ?
        "latest-request" :
        "insufficient-scans";

      res.json({
        plan: latestPlan ?? DEFAULT_PLAN,
        meta: {
          source: metaSource,
          unchanged: !didGenerate,
          reason: metaReason,
          inputHash: didGenerate ? inputHash : latestPlanInputHash,
          updatedAt: latestPlanUpdatedAtIso,
          totalScans: totalScanCount,
          scansUntilNextPlan,
          scansSinceLastPlan,
          latestPlanScanCount,
          planAvailable,
          nextPlanAtScanCount:
            planAvailable && typeof latestPlanScanCount === "number" ?
              latestPlanScanCount + PLAN_REFRESH_INTERVAL :
              PLAN_MIN_SCANS_FOR_PERSONALIZED_PLAN,
          refreshInterval: PLAN_REFRESH_INTERVAL,
        },
      });
    } catch (error) {
      logger.error("Failed to load latest plan", error);
      res.status(500).json({error: "Internal server error"});
    }
  }
);

/**
 * Formats a history snapshot into a readable string for the AI prompt.
 * @param {PlanHistorySnapshot} snapshot - The snapshot to format.
 * @param {number} index - Index within the history array.
 * @return {string} Formatted description of the snapshot.
 */
function formatHistorySnapshot(
  snapshot: PlanHistorySnapshot,
  index: number
): string {
  const position = index + 1;
  const tagSummary = snapshot.lifestyleTags.length > 0 ?
    snapshot.lifestyleTags.join(", ") :
    "none";
  const takeaway = snapshot.personalTakeaway || "none";

  return [
    `S${position}`,
    `score ${snapshot.whitenessScore}/100`,
    `shade ${snapshot.shade}`,
    `tags ${tagSummary}`,
    `takeaway ${takeaway}`,
  ].join(" | ");
}

/**
 * Converts a stored scan document into a PlanHistorySnapshot.
 * @param {FirebaseFirestore.QueryDocumentSnapshot} doc - Firestore doc.
 * @return {PlanHistorySnapshot | null} Snapshot or null when invalid.
 */
function planSnapshotFromScanDoc(
  doc: FirebaseFirestore.QueryDocumentSnapshot
): PlanHistorySnapshot | null {
  const data = doc.data() as Partial<AnalyzeResponse> & {
    createdAt?: FirebaseFirestore.Timestamp | string;
    contextTags?: unknown;
  };

  if (!data?.result) {
    return null;
  }

  const {result} = data;
  if (
    typeof result.whitenessScore !== "number" ||
    typeof result.shade !== "string"
  ) {
    return null;
  }

  const detectedIssues = Array.isArray(result.detectedIssues) ?
    result.detectedIssues
      .filter((issue): issue is DetectedIssue =>
        !!issue &&
        typeof issue === "object" &&
        typeof (issue as DetectedIssue).key === "string" &&
        typeof (issue as DetectedIssue).severity === "string" &&
        typeof (issue as DetectedIssue).notes === "string"
      )
      .sort((a, b) => {
        const keyCompare = a.key.localeCompare(b.key);
        if (keyCompare !== 0) return keyCompare;
        return a.severity.localeCompare(b.severity);
      }) :
    [];

  const contextTagsRaw = Array.isArray(data.contextTags) ?
    data.contextTags :
    [];
  const lifestyleTags = contextTagsRaw
    .map((tag) => typeof tag === "string" ? promptKeywordForTagId(tag) : null)
    .filter((tag): tag is string => !!tag);

  const capturedAtTimestamp =
    data.createdAt instanceof admin.firestore.Timestamp ?
      data.createdAt :
      typeof data.createdAt === "string" ?
        admin.firestore.Timestamp.fromDate(new Date(data.createdAt)) :
        doc.createTime;

  const capturedAt =
    capturedAtTimestamp instanceof admin.firestore.Timestamp ?
      capturedAtTimestamp.toDate().toISOString() :
      new Date().toISOString();

  return {
    capturedAt,
    whitenessScore: result.whitenessScore,
    shade: result.shade,
    detectedIssues,
    lifestyleTags,
    personalTakeaway: typeof result.personalTakeaway === "string" ?
      result.personalTakeaway.trim() :
      "",
  };
}

interface PlanContextData {
  userRef: FirebaseFirestore.DocumentReference;
  userData: LatestPlanDocument;
  history: PlanHistorySnapshot[];
  totalScanCount: number;
}

/**
 * Loads the latest plan context and metadata for the user.
 * @param {string} uid - Firebase auth user id.
 * @return {Promise<PlanContextData>} Context data for plan generation.
 */
async function loadPlanContext(uid: string): Promise<PlanContextData> {
  const userRef = admin.firestore().collection("users").doc(uid);
  const historyRef = userRef.collection("scanResults");

  const [historySnapshot, userSnapshot] = await Promise.all([
    historyRef
      .orderBy("createdAt", "desc")
      .limit(PLAN_CONTEXT_SCAN_LIMIT)
      .get(),
    userRef.get(),
  ]);

  const userData = userSnapshot.exists ?
    userSnapshot.data() as LatestPlanDocument :
    {};

  let totalScanCount = typeof userData.totalScanCount === "number" ?
    userData.totalScanCount :
    undefined;

  if (typeof totalScanCount !== "number") {
    try {
      const aggregateSnapshot = await historyRef.count().get();
      totalScanCount = aggregateSnapshot.data().count;
      await userRef.set({
        totalScanCount,
        totalScanCountResolvedAt: admin.firestore.Timestamp.now(),
      }, {merge: true});
    } catch (error) {
      logger.warn("Failed to aggregate total scan count", {
        uid,
        error: error instanceof Error ? error.message : error,
      });
      if (typeof totalScanCount !== "number") {
        const fallbackSnapshot = await historyRef.select("createdAt").get();
        totalScanCount = fallbackSnapshot.size;
      }
    }
  }

  const history = historySnapshot.docs
    .map((doc) => planSnapshotFromScanDoc(doc))
    .filter((snapshot): snapshot is PlanHistorySnapshot => snapshot !== null);

  history.sort((a, b) => {
    const timeA = new Date(a.capturedAt).getTime();
    const timeB = new Date(b.capturedAt).getTime();
    return timeB - timeA;
  });

  return {
    userRef,
    userData,
    history,
    totalScanCount: totalScanCount ?? 0,
  };
}

/**
 * Recomputes and stores scan counters after history mutations.
 * @param {string} uid - Firebase auth user id.
 * @return {Promise<void>} Resolves when counters are updated.
 */
async function refreshUserScanCounters(uid: string): Promise<void> {
  const userRef = admin.firestore().collection("users").doc(uid);
  const historyRef = userRef.collection("scanResults");

  const aggregateSnapshot = await historyRef.count().get();
  const totalScanCount = aggregateSnapshot.data().count;

  await admin.firestore().runTransaction(async (tx) => {
    const snapshot = await tx.get(userRef);
    const userData = snapshot.exists ?
      snapshot.data() as LatestPlanDocument :
      {};

    const update: Record<string, unknown> = {
      totalScanCount,
    };

    if (typeof userData.latestPlanScanCount === "number") {
      update.latestPlanScanCount = Math.min(
        userData.latestPlanScanCount,
        totalScanCount
      );
    }

    tx.set(userRef, update, {merge: true});
  });
}

/**
 * Computes a deterministic hash for plan history snapshots.
 * @param {PlanHistorySnapshot[]} history - History snapshots to hash.
 * @return {string} SHA-256 hash string.
 */
function computePlanHistoryHash(history: PlanHistorySnapshot[]): string {
  return createHash("sha256")
    .update(JSON.stringify(history))
    .digest("hex");
}

interface GeneratedPlanResult {
  plan: Recommendations;
  createdAt: FirebaseFirestore.Timestamp;
}

/**
 * Generates, stores, and returns a personalized plan for the user.
 * @param {string} uid - Firebase auth user id.
 * @param {PlanHistorySnapshot[]} history - Recent scan history snapshots.
 * @param {number} totalScanCount - Total scans completed by the user.
 * @param {string} inputHash - Hash representing the plan input context.
 * @return {Promise<GeneratedPlanResult>} Generated plan result.
 */
async function generatePlanForUser(
  uid: string,
  history: PlanHistorySnapshot[],
  totalScanCount: number,
  inputHash: string
): Promise<GeneratedPlanResult> {
  if (history.length === 0) {
    throw new Error("Cannot generate plan without history");
  }

  const historyText = history
    .map((snapshot, index) =>
      formatHistorySnapshot(snapshot, index))
    .join("\n");

  const lifestyleThemes = Array.from(
    new Set(
      history.flatMap((snapshot) => snapshot.lifestyleTags)
    )
  ).slice(0, 4);

  const recentTakeaways = history
    .map((snapshot) => snapshot.personalTakeaway)
    .filter((text) => typeof text === "string" && text.trim().length > 0)
    .slice(0, 3);

  const recentScores = history
    .map((snapshot) => snapshot.whitenessScore)
    .filter((score) => typeof score === "number");

  const latestSnapshot = history[0];
  const previousSnapshot = history.length > 1 ? history[1] : null;

  const latestTagIds = Array.from(
    new Set(
      latestSnapshot.lifestyleTags
        .map((tag) => tagIdFromPromptKeyword(tag.toLowerCase()))
        .filter((tagId): tagId is string => !!tagId)
    )
  );

  const previousTagIdsInPlan = previousSnapshot ?
    Array.from(
      new Set(
        previousSnapshot.lifestyleTags
          .map((tag) => tagIdFromPromptKeyword(tag.toLowerCase()))
          .filter((tagId): tagId is string => !!tagId)
      )
    ) :
    [];

  const relapseTagLabels = latestTagIds
    .filter((id) => !previousTagIdsInPlan.includes(id))
    .map((id) => friendlyLabelForTagId(id));

  const regainedTagLabels = previousTagIdsInPlan
    .filter((id) => !latestTagIds.includes(id))
    .map((id) => friendlyLabelForTagId(id));

  const scoreDelta = previousSnapshot ?
    latestSnapshot.whitenessScore - previousSnapshot.whitenessScore :
    null;

  const contextLines: string[] = [];
  if (recentScores.length > 0) {
    contextLines.push(
      "Recent whiteness scores (latest first): " +
        `${recentScores.join(", ")}.`
    );
  }

  if (typeof scoreDelta === "number") {
    contextLines.push(
      "Latest score change vs prior scan: " +
        `${scoreDelta >= 0 ? "+" : ""}${scoreDelta}.`
    );
  }

  if (relapseTagLabels.length > 0) {
    contextLines.push(
      "New stain triggers this scan: " +
        `${relapseTagLabels.join(", ")}.`
    );
  }

  if (regainedTagLabels.length > 0) {
    contextLines.push(
      "Tags the member just improved on: " +
        `${regainedTagLabels.join(", ")}.`
    );
  }

  if (lifestyleThemes.length > 0) {
    contextLines.push(
      "Recurring lifestyle themes: " +
        `${lifestyleThemes.join(", ")}.`
    );
  }

  if (recentTakeaways.length > 0) {
    contextLines.push(
      "Recent takeaways to echo or advance: " +
        `${recentTakeaways.join(" | ")}.`
    );
  }

  const userText = [
    "Design a whitening routine that feels personal and actionable.",
    `Use insights from the last ${history.length} scans (max 10).`,
    ...contextLines,
    "History (latest first):",
    historyText,
  ].join("\n");

  const response = await openai.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [
      {
        role: "system",
        content:
          "You are Gleam's whitening routine architect. " +
          `Create concise, motivating care plans that fit everyday life.
Return ONLY valid JSON that matches this schema exactly:
{
  "plan": {
    "immediate": string[],
    "daily": string[],
    "weekly": string[],
    "caution": string[]
  }
}
Guidance:
- Provide 1-2 items per section; keep each action vivid, ≤ 14 words.
- Reference shade trends or lifestyle tags when relevant.
- If new stain tags appeared, include a recovery cue for them.
- If momentum is strong, end one item with short encouragement.
- Avoid clinical or unsafe treatments; stay at-home friendly.
`,
      },
      {
        role: "user",
        content: userText,
      },
    ],
    response_format: {type: "json_object"},
    temperature: 0.2,
    max_tokens: 320,
  });

  const content = response.choices[0].message.content;
  if (!content) {
    throw new Error("Empty response from OpenAI");
  }

  const parsed = JSON.parse(content) as PlanResponsePayload;
  const createdAt = admin.firestore.Timestamp.now();

  await setLatestPlan(uid, parsed.plan, inputHash, createdAt, totalScanCount);
  void clearLegacyPlanCache(uid);

  logger.info("Plan generated", {
    uid,
    inputHash,
    planSource: "openai",
    historyCount: history.length,
    tokenCost: "estimated",
    totalScanCount,
  });

  return {
    plan: parsed.plan,
    createdAt,
  };
}
