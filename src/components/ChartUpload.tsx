'use client';

import { useCallback, useRef, useState } from 'react';

interface ChartUploadProps {
  onImageSelect: (file: File) => void;
  imagePreview: string | null;
  onAnalyze: () => void;
  onReset: () => void;
  loading: boolean;
  hasResult: boolean;
}

export function ChartUpload({
  onImageSelect,
  imagePreview,
  onAnalyze,
  onReset,
  loading,
  hasResult,
}: ChartUploadProps) {
  const [isDragging, setIsDragging] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleFile = useCallback(
    (file: File) => {
      if (file.type.startsWith('image/')) {
        onImageSelect(file);
      }
    },
    [onImageSelect],
  );

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault();
      setIsDragging(false);
      const file = e.dataTransfer.files[0];
      if (file) handleFile(file);
    },
    [handleFile],
  );

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(true);
  }, []);

  const handleDragLeave = useCallback(() => {
    setIsDragging(false);
  }, []);

  const handleClick = useCallback(() => {
    fileInputRef.current?.click();
  }, []);

  const handleInputChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (file) handleFile(file);
    },
    [handleFile],
  );

  if (imagePreview) {
    return (
      <div className="flex flex-col gap-4">
        <div className="relative rounded-xl overflow-hidden border border-border bg-bg-card">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={imagePreview}
            alt="Chart preview"
            className="w-full max-h-[400px] object-contain"
          />
          {loading && (
            <div className="absolute inset-0 bg-bg-primary/80 flex items-center justify-center">
              <div className="flex flex-col items-center gap-3">
                <div className="relative">
                  <div className="w-12 h-12 border-2 border-info/30 rounded-full" />
                  <div className="absolute inset-0 w-12 h-12 border-2 border-info border-t-transparent rounded-full animate-spin" />
                </div>
                <p className="text-sm text-text-secondary animate-pulse-glow">
                  Analisi in corso...
                </p>
              </div>
            </div>
          )}
        </div>
        <div className="flex gap-3">
          {!hasResult && !loading && (
            <button
              onClick={onAnalyze}
              className="flex-1 py-2.5 px-4 bg-info hover:bg-info/80 text-white font-medium rounded-lg transition-colors"
            >
              Analizza Grafico
            </button>
          )}
          <button
            onClick={onReset}
            disabled={loading}
            className="py-2.5 px-4 bg-bg-card hover:bg-bg-card-hover text-text-secondary font-medium rounded-lg transition-colors border border-border disabled:opacity-50"
          >
            {hasResult ? 'Nuova Analisi' : 'Rimuovi'}
          </button>
        </div>
      </div>
    );
  }

  return (
    <div
      onDrop={handleDrop}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onClick={handleClick}
      className={`relative flex flex-col items-center justify-center gap-4 p-12 rounded-xl border-2 border-dashed cursor-pointer transition-all ${
        isDragging
          ? 'border-info bg-info/5'
          : 'border-border hover:border-border-active hover:bg-bg-card/50'
      }`}
    >
      <input
        ref={fileInputRef}
        type="file"
        accept="image/*"
        onChange={handleInputChange}
        className="hidden"
      />
      <div className="w-16 h-16 rounded-2xl bg-bg-card flex items-center justify-center">
        <svg
          width="32"
          height="32"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.5"
          className="text-text-muted"
        >
          <rect x="3" y="3" width="18" height="18" rx="2" />
          <circle cx="8.5" cy="8.5" r="1.5" />
          <polyline points="21 15 16 10 5 21" />
        </svg>
      </div>
      <div className="text-center">
        <p className="text-sm font-medium text-text-primary">
          Trascina uno screenshot del grafico
        </p>
        <p className="text-xs text-text-muted mt-1">
          oppure clicca per selezionare (PNG, JPG)
        </p>
      </div>
    </div>
  );
}
