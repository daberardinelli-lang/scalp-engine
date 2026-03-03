import type { AIProvider, AnalysisResponse } from '../types';
import { analyzeWithClaude } from './claude-provider';
import { analyzeWithGemini } from './gemini-provider';

function isProviderConfigured(provider: AIProvider): boolean {
  if (provider === 'claude') {
    const key = process.env.ANTHROPIC_API_KEY;
    return !!key && !key.startsWith('your-');
  }
  const key = process.env.GOOGLE_GEMINI_API_KEY;
  return !!key && !key.startsWith('your-');
}

function callProvider(provider: AIProvider, imageBase64: string, mimeType: string) {
  return provider === 'claude'
    ? analyzeWithClaude(imageBase64, mimeType)
    : analyzeWithGemini(imageBase64, mimeType);
}

export async function analyzeChart(
  imageBase64: string,
  mimeType: string,
  provider: AIProvider,
): Promise<AnalysisResponse> {
  const start = Date.now();
  const fallback: AIProvider = provider === 'claude' ? 'gemini' : 'claude';

  try {
    const analysis = await callProvider(provider, imageBase64, mimeType);
    return { analysis, provider, duration: Date.now() - start };
  } catch (primaryError) {
    console.error(`[SCALP ENGINE] ${provider} failed:`, primaryError);

    // Only try fallback if the other provider is configured
    if (isProviderConfigured(fallback)) {
      try {
        const analysis = await callProvider(fallback, imageBase64, mimeType);
        return { analysis, provider: fallback, duration: Date.now() - start };
      } catch (fallbackError) {
        console.error(`[SCALP ENGINE] ${fallback} fallback also failed:`, fallbackError);
      }
    }

    throw new Error(
      primaryError instanceof Error ? primaryError.message : 'Analysis failed',
    );
  }
}
