import type { Verdict } from '@/lib/types';

interface VerdictBadgeProps {
  verdict: Verdict;
  size?: 'sm' | 'lg';
}

const VERDICT_CONFIG: Record<Verdict, { bg: string; text: string; icon: string }> = {
  'BUY': { bg: 'bg-bull/20', text: 'text-bull', icon: '🟢' },
  'LEAN BUY': { bg: 'bg-lean/20', text: 'text-lean', icon: '🟡' },
  'HOLD': { bg: 'bg-hold/20', text: 'text-hold', icon: '⚪' },
  'LEAN SELL': { bg: 'bg-lean/20', text: 'text-lean', icon: '🟡' },
  'SELL': { bg: 'bg-bear/20', text: 'text-bear', icon: '🔴' },
};

export function VerdictBadge({ verdict, size = 'lg' }: VerdictBadgeProps) {
  const config = VERDICT_CONFIG[verdict];

  if (size === 'sm') {
    return (
      <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-medium ${config.bg} ${config.text}`}>
        {config.icon} {verdict}
      </span>
    );
  }

  return (
    <div className={`inline-flex items-center gap-2 px-4 py-2 rounded-lg ${config.bg}`}>
      <span className="text-lg">{config.icon}</span>
      <span className={`text-lg font-bold ${config.text}`}>{verdict}</span>
    </div>
  );
}
