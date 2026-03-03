'use client';

import { useState, useEffect, useCallback } from 'react';
import type { HistoryEntry, AnalysisResult } from '@/lib/types';
import { getHistory, clearHistory, removeFromHistory } from '@/lib/history';
import { VerdictBadge } from './VerdictBadge';

interface HistorySidebarProps {
  onSelect: (entry: HistoryEntry) => void;
  currentId?: string;
  refreshKey: number;
}

export function HistorySidebar({ onSelect, currentId, refreshKey }: HistorySidebarProps) {
  const [history, setHistory] = useState<HistoryEntry[]>([]);
  const [isOpen, setIsOpen] = useState(true);

  useEffect(() => {
    setHistory(getHistory());
  }, [refreshKey]);

  const handleClear = useCallback(() => {
    clearHistory();
    setHistory([]);
  }, []);

  const handleRemove = useCallback((e: React.MouseEvent, id: string) => {
    e.stopPropagation();
    removeFromHistory(id);
    setHistory(getHistory());
  }, []);

  return (
    <aside
      className={`flex flex-col border-r border-border bg-bg-card/50 transition-all ${
        isOpen ? 'w-72' : 'w-12'
      }`}
    >
      {/* Toggle button */}
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="flex items-center justify-center h-12 border-b border-border hover:bg-bg-card-hover transition-colors"
      >
        <svg
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          className={`text-text-muted transition-transform ${isOpen ? '' : 'rotate-180'}`}
        >
          <polyline points="15 18 9 12 15 6" />
        </svg>
      </button>

      {isOpen && (
        <>
          {/* Header */}
          <div className="flex items-center justify-between px-4 py-3 border-b border-border">
            <h2 className="text-sm font-semibold text-text-primary">Storico</h2>
            {history.length > 0 && (
              <button
                onClick={handleClear}
                className="text-xs text-text-muted hover:text-bear transition-colors"
              >
                Svuota
              </button>
            )}
          </div>

          {/* List */}
          <div className="flex-1 overflow-y-auto">
            {history.length === 0 ? (
              <div className="p-4 text-center">
                <p className="text-xs text-text-muted">Nessuna analisi</p>
              </div>
            ) : (
              <div className="flex flex-col">
                {history.map((entry) => (
                  <button
                    key={entry.id}
                    onClick={() => onSelect(entry)}
                    className={`flex items-start gap-3 p-3 text-left hover:bg-bg-card-hover transition-colors border-b border-border/50 group ${
                      currentId === entry.id ? 'bg-bg-card-hover' : ''
                    }`}
                  >
                    {/* Thumbnail */}
                    {entry.imagePreview && (
                      /* eslint-disable-next-line @next/next/no-img-element */
                      <img
                        src={entry.imagePreview}
                        alt=""
                        className="w-10 h-10 rounded object-cover flex-shrink-0"
                      />
                    )}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between gap-1">
                        <span className="text-xs font-mono text-text-primary truncate">
                          {entry.ticker || 'Chart'}
                        </span>
                        <button
                          onClick={(e) => handleRemove(e, entry.id)}
                          className="opacity-0 group-hover:opacity-100 text-text-muted hover:text-bear transition-all"
                        >
                          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                            <line x1="18" y1="6" x2="6" y2="18" />
                            <line x1="6" y1="6" x2="18" y2="18" />
                          </svg>
                        </button>
                      </div>
                      <div className="flex items-center gap-2 mt-1">
                        {entry.verdict && (
                          <VerdictBadge verdict={entry.verdict} size="sm" />
                        )}
                      </div>
                      <div className="flex items-center gap-2 mt-1">
                        <span className={`text-[10px] ${
                          entry.provider === 'claude' ? 'text-claude' : 'text-gemini'
                        }`}>
                          {entry.provider === 'claude' ? 'Claude' : 'Gemini'}
                        </span>
                        <span className="text-[10px] text-text-muted">
                          {new Date(entry.timestamp).toLocaleString('it-IT', {
                            day: '2-digit',
                            month: '2-digit',
                            hour: '2-digit',
                            minute: '2-digit',
                          })}
                        </span>
                      </div>
                    </div>
                  </button>
                ))}
              </div>
            )}
          </div>
        </>
      )}
    </aside>
  );
}
