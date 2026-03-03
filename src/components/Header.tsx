'use client';

import type { AIProvider } from '@/lib/types';

interface HeaderProps {
  provider: AIProvider;
  onProviderChange: (provider: AIProvider) => void;
}

export function Header({ provider, onProviderChange }: HeaderProps) {
  return (
    <header className="flex items-center justify-between px-6 py-4 border-b border-border">
      <div className="flex items-center gap-3">
        <div className="w-8 h-8 rounded-lg bg-bull/20 flex items-center justify-center">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="text-bull">
            <polyline points="22 7 13.5 15.5 8.5 10.5 2 17" />
            <polyline points="16 7 22 7 22 13" />
          </svg>
        </div>
        <h1 className="text-lg font-bold tracking-tight text-text-primary">
          SCALP ENGINE
        </h1>
        <span className="text-xs font-mono text-text-muted bg-bg-card px-2 py-0.5 rounded">
          v2
        </span>
      </div>

      <div className="flex items-center gap-2 bg-bg-card rounded-lg p-1">
        <button
          onClick={() => onProviderChange('gemini')}
          className={`px-3 py-1.5 rounded-md text-sm font-medium transition-all ${
            provider === 'gemini'
              ? 'bg-gemini/20 text-gemini'
              : 'text-text-muted hover:text-text-secondary'
          }`}
        >
          Gemini
        </button>
        <button
          onClick={() => onProviderChange('claude')}
          className={`px-3 py-1.5 rounded-md text-sm font-medium transition-all ${
            provider === 'claude'
              ? 'bg-claude/20 text-claude'
              : 'text-text-muted hover:text-text-secondary'
          }`}
        >
          Claude
        </button>
      </div>
    </header>
  );
}
