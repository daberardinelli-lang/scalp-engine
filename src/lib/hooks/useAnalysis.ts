'use client';

import { useState, useCallback } from 'react';
import type { AIProvider, AnalysisResult, Verdict } from '../types';
import { addToHistory } from '../history';

function extractVerdict(text: string): Verdict | null {
  if (/🟢\s*BUY\b/i.test(text) || /\*\*.*BUY\*\*/i.test(text) && !/LEAN\s*BUY/i.test(text)) {
    // Check it's not LEAN BUY
    if (/LEAN\s*BUY/i.test(text.match(/🟢.*|BUY.*/i)?.[0] ?? '')) return 'LEAN BUY';
    return 'BUY';
  }
  if (/🟡\s*LEAN\s*BUY/i.test(text)) return 'LEAN BUY';
  if (/🔴\s*SELL\b/i.test(text) || /\*\*.*SELL\*\*/i.test(text) && !/LEAN\s*SELL/i.test(text)) {
    if (/LEAN\s*SELL/i.test(text.match(/🔴.*|SELL.*/i)?.[0] ?? '')) return 'LEAN SELL';
    return 'SELL';
  }
  if (/🟡\s*LEAN\s*SELL/i.test(text)) return 'LEAN SELL';
  if (/⚪\s*HOLD/i.test(text)) return 'HOLD';

  // Fallback: search for keywords
  const lower = text.toLowerCase();
  if (lower.includes('lean buy')) return 'LEAN BUY';
  if (lower.includes('lean sell')) return 'LEAN SELL';
  if (/\bbuy\b/.test(lower) && lower.includes('verdetto')) return 'BUY';
  if (/\bsell\b/.test(lower) && lower.includes('verdetto')) return 'SELL';
  if (/\bhold\b/.test(lower) && lower.includes('verdetto')) return 'HOLD';

  return null;
}

function extractTicker(text: string): string | null {
  // Try to find ticker mentions like "AAPL", "EUR/USD", "BTC/USD"
  const forexMatch = text.match(/\b([A-Z]{3}\/[A-Z]{3})\b/);
  if (forexMatch) return forexMatch[1];

  const tickerMatch = text.match(/\b([A-Z]{1,5})\b.*(?:ticker|strumento|instrument)/i);
  if (tickerMatch) return tickerMatch[1];

  const reverseMatch = text.match(/(?:ticker|strumento|instrument)[:\s]*\*?\*?([A-Z]{1,5}(?:\/[A-Z]{3})?)\b/i);
  if (reverseMatch) return reverseMatch[1];

  return null;
}

function generateId(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

export function useAnalysis() {
  const [provider, setProvider] = useState<AIProvider>('gemini');
  const [image, setImage] = useState<string | null>(null);
  const [imageMimeType, setImageMimeType] = useState<string>('image/png');
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [result, setResult] = useState<AnalysisResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleImageSelect = useCallback((file: File) => {
    setError(null);
    setResult(null);
    setImageMimeType(file.type || 'image/png');

    const reader = new FileReader();
    reader.onload = (e) => {
      const dataUrl = e.target?.result as string;
      setImagePreview(dataUrl);
      // Extract base64 data (remove data:image/...;base64, prefix)
      const base64 = dataUrl.split(',')[1];
      setImage(base64);
    };
    reader.readAsDataURL(file);
  }, []);

  const analyze = useCallback(async () => {
    if (!image) return;

    setLoading(true);
    setError(null);

    try {
      const res = await fetch('/api/analyze', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          image,
          mimeType: imageMimeType,
          provider,
        }),
      });

      const data = await res.json();

      if (!res.ok) {
        throw new Error(data.error || `HTTP ${res.status}`);
      }

      const analysisResult: AnalysisResult = {
        id: generateId(),
        analysis: data.analysis,
        provider: data.provider,
        duration: data.duration,
        timestamp: Date.now(),
        verdict: extractVerdict(data.analysis),
        ticker: extractTicker(data.analysis),
        imagePreview: imagePreview || '',
      };

      setResult(analysisResult);

      // Save to history
      addToHistory({
        id: analysisResult.id,
        timestamp: analysisResult.timestamp,
        ticker: analysisResult.ticker,
        verdict: analysisResult.verdict,
        provider: analysisResult.provider,
        analysis: analysisResult.analysis,
        imagePreview: imagePreview || '',
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Analysis failed');
    } finally {
      setLoading(false);
    }
  }, [image, imageMimeType, imagePreview, provider]);

  const reset = useCallback(() => {
    setImage(null);
    setImagePreview(null);
    setResult(null);
    setError(null);
  }, []);

  return {
    provider,
    setProvider,
    image,
    imagePreview,
    result,
    setResult,
    loading,
    error,
    handleImageSelect,
    analyze,
    reset,
  };
}
