import { GoogleGenAI } from '@google/genai';
import { SCALP_ENGINE_SYSTEM_PROMPT } from './system-prompt';

const genai = new GoogleGenAI({ apiKey: process.env.GOOGLE_GEMINI_API_KEY ?? '' });

export async function analyzeWithGemini(imageBase64: string, mimeType: string): Promise<string> {
  const response = await genai.models.generateContent({
    model: 'gemini-2.5-flash',
    config: {
      systemInstruction: SCALP_ENGINE_SYSTEM_PROMPT,
    },
    contents: [
      {
        role: 'user',
        parts: [
          {
            inlineData: {
              mimeType,
              data: imageBase64,
            },
          },
          {
            text: 'Analizza questo grafico secondo il protocollo SCALP ENGINE completo.',
          },
        ],
      },
    ],
  });

  const text = response.text;
  if (!text) {
    throw new Error('No text response from Gemini');
  }
  return text;
}
