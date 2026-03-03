export type AIProvider = 'claude' | 'gemini';

export type Verdict = 'BUY' | 'LEAN BUY' | 'HOLD' | 'LEAN SELL' | 'SELL';

export interface AnalysisResult {
  id: string;
  analysis: string;
  provider: AIProvider;
  duration: number;
  timestamp: number;
  verdict: Verdict | null;
  ticker: string | null;
  imagePreview: string;
}

export interface AnalysisRequest {
  image: string;
  provider: AIProvider;
}

export interface AnalysisResponse {
  analysis: string;
  provider: AIProvider;
  duration: number;
  error?: string;
}

export interface HistoryEntry {
  id: string;
  timestamp: number;
  ticker: string | null;
  verdict: Verdict | null;
  provider: AIProvider;
  analysis: string;
  imagePreview: string;
}
