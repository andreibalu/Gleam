/**
 * Firebase Cloud Functions for Gleam
 * Dental analysis powered by OpenAI GPT-4o-mini
 */

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
  result: ScanResult;
  contextTags?: string[];
  createdAt?: FirebaseFirestore.Timestamp;
}

interface PlanHistorySnapshot {
  capturedAt: string;
  whitenessScore: number;
  shade: string;
  detectedIssues: DetectedIssue[];
  lifestyleTags: string[];
  personalTakeaway: string;
}

interface PlanRequestPayload {
  history: PlanHistorySnapshot[];
}

interface PlanResponsePayload {
  plan: Recommendations;
}

const LIFESTYLE_TAG_LABELS: Record<string, string> = {
  coffee: "coffee",
  red_wine: "red wine",
  cola: "cola & soda",
  tea: "tea",
  smoking: "smoking",
};

const KNOWN_LIFESTYLE_TAG_IDS = Object.keys(LIFESTYLE_TAG_LABELS);

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
        (rawTags as unknown[])
          .filter((tag): tag is string =>
            typeof tag === "string" && tag.trim().length > 0)
          .map((tag) => tag.trim()) :
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

      const tagHistorySummaries = tagHistory.length > 0 ?
        tagHistory.map((entry, index) => {
          const labelIndex = index + 1;
          if (entry.length === 0) {
            return `Scan ${labelIndex}: no lifestyle tags selected`;
          }
          const tagsText = entry
            .map((tagId) => LIFESTYLE_TAG_LABELS[tagId] ?? tagId)
            .join(", ");
          return `Scan ${labelIndex}: ${tagsText}`;
        }) :
        [];

      const tagUsageCounts = KNOWN_LIFESTYLE_TAG_IDS.reduce(
        (accumulator, tagId) => {
          accumulator[tagId] = 0;
          return accumulator;
        },
        {} as Record<string, number>
      );

      tagHistory.forEach((entry) => {
        const seen = new Set(entry);
        seen.forEach((tagId) => {
          if (tagUsageCounts[tagId] !== undefined) {
            tagUsageCounts[tagId] += 1;
          }
        });
      });

      const totalTagSamples = tagHistory.length;

      const tagUsageSummary = totalTagSamples > 0 ?
        KNOWN_LIFESTYLE_TAG_IDS
          .map((tagId) => {
            const friendly = LIFESTYLE_TAG_LABELS[tagId] ?? tagId;
            const count = tagUsageCounts[tagId] ?? 0;
            return `${friendly}: ${count}/${totalTagSamples}`;
          }).join(", ") :
        "";

      const positiveStreaks = totalTagSamples > 0 ?
        KNOWN_LIFESTYLE_TAG_IDS
          .filter((tagId) => (tagUsageCounts[tagId] ?? 0) === 0)
          .map((tagId) => LIFESTYLE_TAG_LABELS[tagId] ?? tagId) :
        [];

      const positiveHighlights = positiveStreaks.slice(0, 2);

      const concernThreshold = totalTagSamples === 0 ?
        0 :
        Math.max(2, Math.ceil(totalTagSamples * 0.5));

      const overusedTags = totalTagSamples > 0 ?
        KNOWN_LIFESTYLE_TAG_IDS
          .map((tagId) => ({
            label: LIFESTYLE_TAG_LABELS[tagId] ?? tagId,
            count: tagUsageCounts[tagId] ?? 0,
          }))
          .filter(({count}) => count >= concernThreshold) :
        [];

      const overusedHighlights = overusedTags.slice(0, 2);

      const userTextParts = [
        "Analyze this teeth photo for whitening insights. " +
        "Provide shade score, focus areas, and confidence level.",
      ];

      if (tags.length > 0) {
        userTextParts.push(
          `Lifestyle tags to weigh: ${tags.join(", ")}.`);
      } else {
        userTextParts.push("No lifestyle tags were selected.");
      }

      if (tagHistorySummaries.length > 0) {
        userTextParts.push(
          `Lifestyle tag history (latest first): ${
            tagHistorySummaries.join(" | ")
          }.`
        );
      } else {
        userTextParts.push(
          "No recorded lifestyle tag history yet; " +
          "treat this scan as a baseline."
        );
      }

      if (tagUsageSummary.length > 0) {
        userTextParts.push(
          `Tag usage counts out of the last ${totalTagSamples} scans: ` +
          `${tagUsageSummary}.`
        );
      }

      if (positiveHighlights.length > 0) {
        userTextParts.push(
          `Celebrate streaks avoiding: ${positiveHighlights.join(", ")}.`
        );
      }

      if (overusedHighlights.length > 0) {
        userTextParts.push(
          "Call out overused tags with gentle guidance: " +
          overusedHighlights
            .map(({label, count}) => `${label} (${count})`)
            .join(", ") +
          "."
        );
      }

      if (previousTakeaways.length > 0) {
        userTextParts.push(
          "Avoid repeating these recent personal takeaways: " +
          `${previousTakeaways.join(" | ")}.`
        );
      } else {
        userTextParts.push(
          "This is the first personal takeaway for this streak.");
      }

      const userText = userTextParts.join(" ");

      const guidanceLines = [
        "- Use Vita shade codes like A2 and keep it to one value.",
        "- Use lifestyle tags (coffee, wine, etc.) throughout the analysis.",
        "- Keep the personal takeaway energetic and concise.",
        "  Aim for roughly 10 words.",
        "  Fold in lifestyle tags and avoid repeating recent takeaways.",
        "- Highlight lifestyle signals.",
        "  Praise zero-use streaks and coach frequent tags.",
        "  If no history exists, focus on sustaining bright habits.",
        "- Two- or three-word takeaways are fine when momentum is the message.",
        "- Keep each detected issue concise with key, severity, and next step.",
        "- Set referralNeeded to true only when clinical follow-up is needed.",
        "- Keep the disclaimer short and in plain language (max 22 words).",
        "- Ensure confidence stays within 0.0 to 1.0 and reflects certainty.",
      ].join("\n");

      logger.info("Processing dental scan analysis", {
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
            content: "You are Gleam's virtual cosmetic dental designer. " +
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
        max_tokens: 500,
      });

      // Parse the result
      const content = response.choices[0].message.content;
      if (!content) {
        throw new Error("Empty response from OpenAI");
      }

      const result = JSON.parse(content) as ScanResult;

      logger.info("Analysis completed successfully", {
        whitenessScore: result.whitenessScore,
        confidence: result.confidence,
      });

      const record: AnalyzeResponse = {
        result,
        contextTags: tags,
      };

      await admin.firestore().collection("scanResults").add({
        ...record,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      res.json(record);
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
    const isLatestRequest = req.path === "/latest" || req.path === "latest";
    if (req.method !== "GET" || !isLatestRequest) {
      res.status(404).json({error: "Not Found"});
      return;
    }

    try {
      const snapshot = await admin
        .firestore()
        .collection("scanResults")
        .orderBy("createdAt", "desc")
        .limit(1)
        .get();

      if (snapshot.empty) {
        res.status(404).json({error: "No scans found"});
        return;
      }

      const data = snapshot.docs[0].data() as AnalyzeResponse;
      res.json({result: data.result});
    } catch (error) {
      logger.error("Failed to load latest scan", error);
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

    try {
      const body = (req.body ?? {}) as PlanRequestPayload;
      const history = Array.isArray(body.history) ?
        body.history
          .slice(0, 5)
          .map((snapshot) => normalizeSnapshot(snapshot))
          .filter((snapshot): snapshot is PlanHistorySnapshot =>
            snapshot !== null) :
        [];

      if (history.length === 0) {
        res.json({plan: DEFAULT_PLAN});
        return;
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

      const contextHints = [
        recentScores.length > 0 ?
          `Recent whiteness scores (latest first): ${
            recentScores.join(", ")
          }.` :
          "",
        lifestyleThemes.length > 0 ?
          `Lifestyle themes to acknowledge: ${lifestyleThemes.join(", ")}.` :
          "",
        recentTakeaways.length > 0 ?
          `Recent encouragements to build on: ${recentTakeaways.join(" | ")}.` :
          "",
      ].filter((hint) => hint.length > 0).join(" ");

      const userText =
        "Craft a compact whitening routine tailored to this person. " +
        "Keep each action hyper-specific to their shade progress, " +
        "detected issues, or lifestyle tags so it feels made for them. " +
        "Highlight safe at-home steps and energizing nudges. " +
        (contextHints.length > 0 ? `${contextHints} ` : "") +
        `History:\n${historyText}`;

      const response = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: "You are Gleam's whitening routine architect. " +
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
- Provide 1-2 items per list; keep actions distinct and tightly focused.
- Max 14 words per item, starting with an action verb that references ` +
              `a relevant detail.
- Mirror the provided lifestyle tags (e.g., coffee) ` +
              `or detected issues with tailored suggestions.
- Reinforce safe pacing; avoid drastic or clinical treatments.
- If history indicates strong momentum, end one item with a short encouragement.
- Avoid generic advice that could apply to anyone.
`,
          },
          {
            role: "user",
            content: userText,
          },
        ],
        response_format: {type: "json_object"},
        temperature: 0.4,
        max_tokens: 600,
      });

      const content = response.choices[0].message.content;
      if (!content) {
        throw new Error("Empty response from OpenAI");
      }

      const parsed = JSON.parse(content) as PlanResponsePayload;
      res.json(parsed);
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

/**
 * Normalizes a raw snapshot payload into a valid PlanHistorySnapshot.
 * @param {unknown} raw - The raw snapshot data to normalize
 * @return {PlanHistorySnapshot | null} Normalized snapshot or null if invalid
 */
function normalizeSnapshot(raw: unknown): PlanHistorySnapshot | null {
  if (typeof raw !== "object" || raw === null) {
    return null;
  }

  const snapshot = raw as Partial<PlanHistorySnapshot>;
  if (typeof snapshot.whitenessScore !== "number" ||
      typeof snapshot.shade !== "string") {
    return null;
  }

  const lifestyleTags = Array.isArray(snapshot.lifestyleTags) ?
    snapshot.lifestyleTags.filter((tag): tag is string =>
      typeof tag === "string" && tag.trim().length > 0) :
    [];

  const detectedIssues = Array.isArray(snapshot.detectedIssues) ?
    snapshot.detectedIssues.filter((issue): issue is DetectedIssue =>
      typeof issue === "object" && issue !== null &&
      typeof (issue as DetectedIssue).key === "string" &&
      typeof (issue as DetectedIssue).severity === "string" &&
      typeof (issue as DetectedIssue).notes === "string") :
    [];

  const capturedAt = typeof snapshot.capturedAt === "string" ?
    snapshot.capturedAt :
    new Date().toISOString();
  const personalTakeaway =
    typeof snapshot.personalTakeaway === "string" ?
      snapshot.personalTakeaway.trim() :
      "";

  return {
    capturedAt,
    whitenessScore: snapshot.whitenessScore,
    shade: snapshot.shade,
    detectedIssues,
    lifestyleTags,
    personalTakeaway,
  };
}

/**
 * Formats a history snapshot into a readable string for the AI prompt.
 * @param {PlanHistorySnapshot} snapshot - The snapshot to format
 * @param {number} index - The index of this snapshot in the history
 * @return {string} Formatted string describing the snapshot
 */
function formatHistorySnapshot(
  snapshot: PlanHistorySnapshot,
  index: number
): string {
  const position = index + 1;
  const tagSummary = snapshot.lifestyleTags.length > 0 ?
    snapshot.lifestyleTags.join(", ") :
    "none";
  const takeaway = snapshot.personalTakeaway || "";

  return `Scan ${position}: score ${snapshot.whitenessScore}/100, ` +
    `shade ${snapshot.shade}, lifestyle tags: ${tagSummary}. ` +
    `Takeaway: ${takeaway}.`;
}
