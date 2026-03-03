'use client';

import { useState, useCallback } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import type { AnalysisResult } from '@/lib/types';
import { VerdictBadge } from './VerdictBadge';

interface AnalysisPanelProps {
  result: AnalysisResult;
}

export function AnalysisPanel({ result }: AnalysisPanelProps) {
  const providerLabel = result.provider === 'claude' ? 'Claude' : 'Gemini';
  const providerColor = result.provider === 'claude' ? 'text-claude' : 'text-gemini';
  const durationSec = (result.duration / 1000).toFixed(1);
  const [copied, setCopied] = useState(false);

  const handleCopy = useCallback(async () => {
    await navigator.clipboard.writeText(result.analysis);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }, [result.analysis]);

  return (
    <div className="flex flex-col gap-4">
      {/* Header with verdict and meta */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-3">
          {result.verdict && <VerdictBadge verdict={result.verdict} />}
          {result.ticker && (
            <span className="text-sm font-mono text-text-secondary bg-bg-card px-2 py-1 rounded">
              {result.ticker}
            </span>
          )}
        </div>
        <div className="flex items-center gap-3 text-xs text-text-muted">
          <span>
            Analizzato da <span className={`font-medium ${providerColor}`}>{providerLabel}</span>
          </span>
          <span>
            {durationSec}s
          </span>
          <span>
            {new Date(result.timestamp).toLocaleTimeString('it-IT')}
          </span>
          <button
            onClick={handleCopy}
            className="flex items-center gap-1 px-2 py-1 rounded hover:bg-bg-card-hover transition-colors text-text-muted hover:text-text-primary"
            title="Copia analisi"
          >
            {copied ? (
              <>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="text-bull">
                  <polyline points="20 6 9 17 4 12" />
                </svg>
                <span className="text-bull">Copiato</span>
              </>
            ) : (
              <>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <rect x="9" y="9" width="13" height="13" rx="2" ry="2" />
                  <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
                </svg>
                <span>Copia</span>
              </>
            )}
          </button>
        </div>
      </div>

      {/* Analysis content */}
      <div className="analysis-content bg-bg-card rounded-xl border border-border p-6 overflow-x-auto">
        <ReactMarkdown remarkPlugins={[remarkGfm]}>
          {result.analysis}
        </ReactMarkdown>
      </div>
    </div>
  );
}
