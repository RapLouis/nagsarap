export type SlotType = 'in' | 'out';
export type WindowState = 'upcoming' | 'open' | 'closed';

type SlotLike = {
    time_in_start?: string | null;
    time_in_end?: string | null;
    time_out_start?: string | null;
    time_out_end?: string | null;
};

/** Minimal shape of an attendance row as sent by Laravel (after the migration). */
export type SlotAttendance = {
    event?: { event_id: number } | null;
    event_id?: number;
    event_date?: string | null; // 'YYYY-MM-DD' (do not cast this column in the model)
    slot_index?: number | string | null;
    type?: SlotType | null;
};

/** Local (device) date as YYYY-MM-DD. toISOString() is UTC and breaks 00:00-08:00 in UTC+8. */
export function localYmd(d: Date = new Date()): string {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
}

function toMinutes(t?: string | null): number | null {
    if (!t) return null;
    const [h, m] = t.split(':').map(Number);
    if (Number.isNaN(h) || Number.isNaN(m)) return null;
    return h * 60 + m;
}

/**
 * State of one window of a slot. Returns null when the slot has no such window.
 * The server stays the authority; this only drives which button/label to show.
 */
export function windowState(
    slot: SlotLike,
    type: SlotType,
    dateStr: string,
    now: Date = new Date(),
): WindowState | null {
    const start = toMinutes(type === 'in' ? slot.time_in_start : slot.time_out_start);
    if (start === null) return null;

    const today = localYmd(now);
    if (dateStr < today) return 'closed';
    if (dateStr > today) return 'upcoming';

    const endRaw = toMinutes(type === 'in' ? slot.time_in_end : slot.time_out_end);
    // No cutoff (or an overnight one) -> open until the end of the day, same as the server.
    const end = endRaw !== null && endRaw > start ? endRaw : 23 * 60 + 59;
    const current = now.getHours() * 60 + now.getMinutes();

    if (current < start) return 'upcoming';
    if (current <= end) return 'open';
    return 'closed';
}

/** Exact match on (event, day, slot, type) - no more time-distance guessing. */
export function findSlotRecord<T extends SlotAttendance>(
    attendances: T[],
    eventId: number,
    dateStr: string,
    slotIndex: number,
    type: SlotType,
): T | undefined {
    return attendances.find(
        (log) =>
            (log.event?.event_id ?? log.event_id) === eventId &&
            (log.event_date ?? '').slice(0, 10) === dateStr &&
            log.slot_index != null &&
            Number(log.slot_index) === slotIndex &&
            log.type === type,
    );
}

export function formatTime(timeStr?: string | null): string {
    if (!timeStr) return '';
    const [h, m] = timeStr.split(':').map(Number);
    const d = new Date();
    d.setHours(h ?? 0, m ?? 0, 0);
    return d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', hour12: true });
}