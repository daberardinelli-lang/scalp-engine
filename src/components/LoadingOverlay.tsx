'use client';

import type { AIProvider } from '@/lib/types';

interface LoadingOverlayProps {
  provider: AIProvider;
}

export function LoadingOverlay({ provider }: LoadingOverlayProps) {
  const providerLabel = provider === 'claude' ? 'Claude' : 'Gemini';
  const providerColor = provider === 'claude' ? 'border-claude' : 'border-gemini';

  return (
    <div className="flex flex-col items-center justify-center py-16 gap-4">
      <div className="relative">
        <div className={`w-16 h-16 border-2 ${providerColor}/30 rounded-full`} />
        <div className={`absolute inset-0 w-16 h-16 border-2 ${providerColor} border-t-transparent rounded-full animate-spin`} />
      </div>
      <div className="text-center">
        <p className="text-sm font-medium text-text-primary">
          Analisi in corso con {providerLabel}...
        </p>
        <p className="text-xs text-text-muted mt-1">
          L&apos;analisi potrebbe richiedere 15-30 secondi
        </p>
      </div>
      <div className="flex gap-1">
        {[0, 1, 2, 3, 4].map((i) => (
          <div
            key={i}
            className="w-1.5 h-1.5 rounded-full bg-text-muted animate-pulse-glow"
            style={{ animationDelay: `${i * 0.2}s` }}
          />
        ))}
      </div>
    </div>
  );
}
