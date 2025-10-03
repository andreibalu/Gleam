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
  recommendations: Recommendations;
  referralNeeded: boolean;
  disclaimer: string;
  planSummary: string;
}

interface AnalyzeResponse {
  result: ScanResult;
  createdAt?: FirebaseFirestore.Timestamp;
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
      // Extract image from request body
      const {image} = req.body as {image?: string};

      if (!image || typeof image !== "string") {
        res.status(400).json({error: "Missing or invalid 'image' field"});
        return;
      }

      logger.info("Processing dental scan analysis");

      // Call OpenAI GPT-4o-mini with vision
      const response = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: `You are a cosmetic dental assistant. 
            Analyze teeth photos and provide whitening recommendations.
Output ONLY valid JSON matching this exact schema:
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
  "recommendations": {
    "immediate": string[],
    "daily": string[],
    "weekly": string[],
    "caution": string[]
  },
  "referralNeeded": boolean,
  "disclaimer": string,
  "planSummary": string
}`,
          },
          {
            role: "user",
            content: [
              {
                type: "text",
                text:
                  "Analyze this teeth photo for whitening recommendations. " +
                  "Provide shade score, specific recommendations, " +
                  "and confidence level.",
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
