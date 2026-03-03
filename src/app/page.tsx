'use client';

import { useCallback, useState } from 'react';
import { Header } from '@/components/Header';
import { ChartUpload } from '@/components/ChartUpload';
import { AnalysisPanel } from '@/components/AnalysisPanel';
import { HistorySidebar } from '@/components/HistorySidebar';
import { LoadingOverlay } from '@/components/LoadingOverlay';
import { useAnalysis } from '@/lib/hooks/useAnalysis';
import type { HistoryEntry } from '@/lib/types';

export default function Home() {
  const {
    provider,
    setProvider,
    imagePreview,
    result,
    setResult,
    loading,
    error,
    handleImageSelect,
    analyze,
    reset,
  } = useAnalysis();

  const [historyRefresh, setHistoryRefresh] = useState(0);

  const handleHistorySelect = useCallback(
    (entry: HistoryEntry) => {
      setResult({
        id: entry.id,
        analysis: entry.analysis,
        provider: entry.provider,
        duration: 0,
        timestamp: entry.timestamp,
        verdict: entry.verdict,
        ticker: entry.ticker,
        imagePreview: entry.imagePreview,
      });
    },
    [setResult],
  );

  const handleAnalyze = useCallback(async () => {
    await analyze();
    setHistoryRefresh((k) => k + 1);
  }, [analyze]);

  return (
    <div className="flex flex-col h-screen">
      <Header provider={provider} onProviderChange={setProvider} />

      <div className="flex flex-1 overflow-hidden">
        <HistorySidebar
          onSelect={handleHistorySelect}
          currentId={result?.id}
          refreshKey={historyRefresh}
        />

        <main className="flex-1 overflow-y-auto p-6 grid-bg">
          <div className="max-w-4xl mx-auto flex flex-col gap-6">
            {/* Upload section */}
            {!loading && (
              <ChartUpload
                onImageSelect={handleImageSelect}
                imagePreview={result?.imagePreview || imagePreview}
                onAnalyze={handleAnalyze}
                onReset={reset}
                loading={loading}
                hasResult={!!result}
              />
            )}

            {/* Loading */}
            {loading && (
              <>
                <ChartUpload
                  onImageSelect={handleImageSelect}
                  imagePreview={imagePreview}
                  onAnalyze={handleAnalyze}
                  onReset={reset}
                  loading={loading}
                  hasResult={false}
                />
                <LoadingOverlay provider={provider} />
              </>
            )}

            {/* Error */}
            {error && (
              <div className="bg-bear/10 border border-bear/30 rounded-xl p-4">
                <div className="flex items-start gap-3">
                  <span className="text-bear text-lg">!</span>
                  <div>
                    <p className="text-sm font-medium text-bear">Errore nell&apos;analisi</p>
                    <p className="text-xs text-text-secondary mt-1">{error}</p>
                  </div>
                </div>
              </div>
            )}

            {/* Results */}
            {result && <AnalysisPanel result={result} />}

            {/* Empty state */}
            {!imagePreview && !result && !loading && (
              <div className="text-center py-16">
                <div className="inline-flex items-center justify-center w-20 h-20 rounded-2xl bg-bg-card mb-4">
                  <svg
                    width="40"
                    height="40"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="1"
                    className="text-text-muted"
                  >
                    <path d="M3 3v18h18" />
                    <path d="M7 16l4-8 4 4 4-6" />
                  </svg>
                </div>
                <h2 className="text-lg font-semibold text-text-primary mb-2">
                  Carica un grafico per iniziare
                </h2>
                <p className="text-sm text-text-muted max-w-md mx-auto">
                  SCALP ENGINE analizzerà il tuo grafico con price action, indicatori tecnici,
                  volume profile e confluenza dei segnali per darti un verdetto operativo.
                </p>
              </div>
            )}
          </div>
        </main>
      </div>
    </div>
  );
}
