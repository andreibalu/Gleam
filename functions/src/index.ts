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
      } = req.body as {
        image?: string;
        tags?: unknown;
        previousTakeaways?: unknown;
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

      if (previousTakeaways.length > 0) {
        userTextParts.push(
          "Avoid repeating these recent personal takeaways: " +
          `${previousTakeaways.join(" | ")}.`);
      } else {
        userTextParts.push(
          "This is the first personal takeaway for this streak.");
      }

      const userText = userTextParts.join(" ");

      logger.info("Processing dental scan analysis", {
        tags,
        previousTakeawaysCount: previousTakeaways.length,
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
- Use Vita shade notation (e.g., "A2") for "shade"; ` +
              `keep it to the single code.
- We will provide optional lifestyle tags (like coffee or red wine). ` +
              `If present, factor them into your observations and issue notes.
- The "personalTakeaway" must be a succinct, energetic line ` +
              "(max 16 words) that does not repeat any of the provided " +
              `recent takeaways.
- You may write the "personalTakeaway" in as few as 2-3 words ` +
              `when momentum is the message (e.g., "Keep going").
- Each "detectedIssues" entry should use a concise key (e.g., "staining"), ` +
              "a severity from the enum, and notes limited to two sentences " +
              `with a clear next step.
- Set "referralNeeded" to true only when clinical signs suggest ` +
              `professional assessment (e.g., severe lesions, suspected decay).
- Keep "disclaimer" short and written in plain language (max 22 words).
- Always ensure "confidence" reflects true model certainty ` +
              `between 0.0 and 1.0.
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
          .slice(0, 3)
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

      const userText =
        "Design an at-home whitening plan split into immediate, daily, " +
        "weekly, and caution actions. Use the user's recent scans and " +
        `lifestyle tags to keep tips relevant. History:\n${historyText}`;

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
- Provide 1-3 items per list; keep actions distinct across lists.
- Max 18 words per item, starting with an action verb.
- Reflect the provided lifestyle tags (e.g., coffee) ` +
              `with specific suggestions.
- Reinforce safe pacing; avoid drastic or clinical treatments.
- If history indicates strong momentum, you may include ` +
              `quick encouragement phrases.
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
  const issueSummary = snapshot.detectedIssues
    .map((issue) => `${issue.key} (${issue.severity})`)
    .join("; ") || "none";
  const tagSummary = snapshot.lifestyleTags.length > 0 ?
    snapshot.lifestyleTags.join(", ") :
    "none";
  const takeaway = snapshot.personalTakeaway || "";

  return `Scan ${position}: score ${snapshot.whitenessScore}/100, ` +
    `shade ${snapshot.shade}, lifestyle tags: ${tagSummary}. ` +
    `Issues: ${issueSummary}. Takeaway: ${takeaway}.`;
}
