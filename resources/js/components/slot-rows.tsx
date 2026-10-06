import React from 'react';
import { Camera, CheckCircle2 } from 'lucide-react';
import type { WindowState } from '../lib/slots';

const GOLD = '#C9973E';

export type SlotBadge = 'open' | 'upcoming' | 'closed' | 'completed';

const BADGE_STYLES: Record<SlotBadge, { label: string; className: string }> = {
    open: {
        label: 'Open now',
        className:
            'bg-emerald-50 text-emerald-700 border-emerald-200 dark:bg-emerald-950/30 dark:text-emerald-400 dark:border-emerald-800/40',
    },
    upcoming: {
        label: 'Upcoming',
        className:
            'bg-amber-50 text-amber-700 border-amber-200 dark:bg-amber-950/30 dark:text-amber-400 dark:border-amber-800/40',
    },
    closed: {
        label: 'Closed',
        className: 'bg-gray-100 text-gray-500 border-gray-200 dark:bg-slate-800 dark:text-gray-400 dark:border-slate-700',
    },
    completed: {
        label: 'Completed',
        className:
            'bg-indigo-50 text-[#1B1F5C] border-indigo-200 dark:bg-slate-800 dark:text-amber-400 dark:border-slate-700',
    },
};

export function SlotStatusBadge({ status }: { status: SlotBadge }) {
    const { label, className } = BADGE_STYLES[status];
    return (
        <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-semibold ${className}`}>
            {label}
        </span>
    );
}

/** Overall status of one slot, derived from both of its windows. */
export function slotBadge(args: {
    hasIn: boolean;
    hasOut: boolean;
    inState: WindowState | null;
    outState: WindowState | null;
    inDone: boolean;
    outDone: boolean;
}): SlotBadge {
    const { hasIn, hasOut, inState, outState, inDone, outDone } = args;

    const allDone = (!hasIn || inDone) && (!hasOut || outDone);
    if (allDone) return 'completed';

    const anyOpen = (hasIn && !inDone && inState === 'open') || (hasOut && !outDone && outState === 'open');
    if (anyOpen) return 'open';

    const anyUpcoming =
        (hasIn && !inDone && inState === 'upcoming') || (hasOut && !outDone && outState === 'upcoming');
    return anyUpcoming ? 'upcoming' : 'closed';
}

type SlotWindowRowProps = {
    label: 'In' | 'Out';
    time: string;
    state: WindowState | null;
    done: boolean;
    doneLabel: string;
    actionLabel: string;
    /** When set, the window is open but the action is unavailable (e.g. "Check in first"). */
    blockedReason?: string | null;
    onAction: () => void;
};

export function SlotWindowRow({
    label,
    time,
    state,
    done,
    doneLabel,
    actionLabel,
    blockedReason,
    onAction,
}: SlotWindowRowProps) {
    return (
        <div className="flex items-center justify-between text-xs">
            <span className="text-gray-500">
                {label}: <strong className="text-gray-800 dark:text-gray-200">{time}</strong>
            </span>

            {done ? (
                <span className="inline-flex items-center gap-1 text-emerald-600 dark:text-emerald-400 font-medium">
                    <CheckCircle2 className="h-3.5 w-3.5" /> {doneLabel}
                </span>
            ) : state === 'open' ? (
                blockedReason ? (
                    <span className="text-gray-400 italic">{blockedReason}</span>
                ) : (
                    <button
                        type="button"
                        onClick={onAction}
                        className="inline-flex items-center gap-1 rounded-lg px-3 py-1 text-xs font-semibold text-white shadow-sm hover:opacity-95"
                        style={{ backgroundColor: GOLD }}
                    >
                        <Camera className="h-3.5 w-3.5" /> {actionLabel}
                    </button>
                )
            ) : state === 'upcoming' ? (
                <span className="text-gray-400">Not open yet</span>
            ) : (
                <span className="text-gray-400 italic">Closed</span>
            )}
        </div>
    );
}