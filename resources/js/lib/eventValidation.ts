export type TimeSlot = {
    has_afternoon?: boolean;
    morning_time_in_start?: string | null;
    morning_time_in_end?: string | null;
    morning_time_out_start?: string | null;
    morning_time_out_end?: string | null;
    afternoon_time_in_start?: string | null;
    afternoon_time_in_end?: string | null;
    afternoon_time_out_start?: string | null;
    afternoon_time_out_end?: string | null;
    // Legacy fallbacks
    time_in_start?: string | null;
    time_in_end?: string | null;
    time_out_start?: string | null;
    time_out_end?: string | null;
    late_after_minutes?: number;
};

export type ScheduleItem = {
    date: string;
    slots: TimeSlot[];
};

/**
 * Validates schedule time slots to ensure chronological sequence and prevent overlaps across all 4 checkpoints.
 */
export const validateTimeSlots = (
    schedules: ScheduleItem[],
    setErrorCallback: (errorMsg: string | null) => void
): boolean => {
    for (const sched of schedules) {
        for (let i = 0; i < sched.slots.length; i++) {
            const slot = sched.slots[i];
            const slotPrefix = `Conflict on ${sched.date} (Slot ${i + 1}):`;

            // 1. Morning Time-In Range
            const mInStart = slot.morning_time_in_start || slot.time_in_start;
            const mInEnd = slot.morning_time_in_end || slot.time_in_end;
            if (mInStart && mInEnd && mInStart >= mInEnd) {
                setErrorCallback(`${slotPrefix} Morning Time-In Start must be earlier than its Cutoff.`);
                return false;
            }

            // 2. Morning Time-Out Range
            const mOutStart = slot.morning_time_out_start || slot.time_out_start;
            const mOutEnd = slot.morning_time_out_end || slot.time_out_end;
            if (mInEnd && mOutStart && mInEnd >= mOutStart) {
                setErrorCallback(`${slotPrefix} Morning Time-In Cutoff cannot overlap or be after Morning Time-Out Start.`);
                return false;
            }
            if (mOutStart && mOutEnd && mOutStart >= mOutEnd) {
                setErrorCallback(`${slotPrefix} Morning Time-Out Start must be earlier than its Cutoff.`);
                return false;
            }

            // 3. Afternoon Session Validation (if enabled)
            const hasAfternoon = Boolean(slot.has_afternoon || slot.afternoon_time_in_start);
            if (hasAfternoon) {
                const aInStart = slot.afternoon_time_in_start;
                const aInEnd = slot.afternoon_time_in_end;
                const aOutStart = slot.afternoon_time_out_start;
                const aOutEnd = slot.afternoon_time_out_end;

                if (mOutEnd && aInStart && mOutEnd >= aInStart) {
                    setErrorCallback(`${slotPrefix} Afternoon session must start after Morning session Cutoff.`);
                    return false;
                }
                if (aInStart && aInEnd && aInStart >= aInEnd) {
                    setErrorCallback(`${slotPrefix} Afternoon Time-In Start must be earlier than its Cutoff.`);
                    return false;
                }
                if (aInEnd && aOutStart && aInEnd >= aOutStart) {
                    setErrorCallback(`${slotPrefix} Afternoon Time-In Cutoff cannot overlap or be after Afternoon Time-Out Start.`);
                    return false;
                }
                if (aOutStart && aOutEnd && aOutStart >= aOutEnd) {
                    setErrorCallback(`${slotPrefix} Afternoon Time-Out Start must be earlier than its Cutoff.`);
                    return false;
                }
            }
        }
    }
    setErrorCallback(null);
    return true;
};

/**
 * Checks if the current browser system time falls within any 
 * active time-in or time-out checkpoint window configured for today's event schedule.
 */
export const isEventWindowOpen = (schedules: ScheduleItem[] | null | undefined): boolean => {
    if (!schedules || schedules.length === 0) return false;

    const now = new Date();
    const todayStr = now.toISOString().split('T')[0]; // YYYY-MM-DD

    const todaySchedule = schedules.find((sched) => sched.date === todayStr);

    if (!todaySchedule || !todaySchedule.slots || todaySchedule.slots.length === 0) {
        return false;
    }

    const currentHours = String(now.getHours()).padStart(2, '0');
    const currentMinutes = String(now.getMinutes()).padStart(2, '0');
    const currentTime = `${currentHours}:${currentMinutes}`;

    return todaySchedule.slots.some((slot) => {
        let slotOpen = false;

        // Check Morning Time-In
        const mInStart = slot.morning_time_in_start || slot.time_in_start;
        const mInEnd = slot.morning_time_in_end || slot.time_in_end || '23:59';
        if (mInStart && currentTime >= mInStart && currentTime <= mInEnd) {
            slotOpen = true;
        }

        // Check Morning Time-Out
        const mOutStart = slot.morning_time_out_start || slot.time_out_start;
        const mOutEnd = slot.morning_time_out_end || slot.time_out_end || '23:59';
        if (mOutStart && currentTime >= mOutStart && currentTime <= mOutEnd) {
            slotOpen = true;
        }

        // Check Afternoon Time-In
        const hasAfternoon = Boolean(slot.has_afternoon || slot.afternoon_time_in_start);
        if (hasAfternoon) {
            const aInStart = slot.afternoon_time_in_start;
            const aInEnd = slot.afternoon_time_in_end || '23:59';
            if (aInStart && currentTime >= aInStart && currentTime <= aInEnd) {
                slotOpen = true;
            }

            // Check Afternoon Time-Out
            const aOutStart = slot.afternoon_time_out_start;
            const aOutEnd = slot.afternoon_time_out_end || '23:59';
            if (aOutStart && currentTime >= aOutStart && currentTime <= aOutEnd) {
                slotOpen = true;
            }
        }

        return slotOpen;
    });
};

export const getEventDays = (startDate: string, endDate: string | null): string[] => {
    if (!startDate) return [];
    if (!endDate || endDate <= startDate) return [startDate];

    const days: string[] = [];
    const current = new Date(startDate + 'T00:00:00');
    const end = new Date(endDate + 'T00:00:00');

    while (current <= end) {
        days.push(current.toISOString().split('T')[0]);
        current.setDate(current.getDate() + 1);
    }
    return days;
};

export const formatDate = (dateStr: string): string => {
    return new Date(dateStr + 'T00:00:00').toLocaleDateString(undefined, {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
    });
};

export const relativeDateLabel = (dateStr: string): string => {
    const eventDate = new Date(dateStr + 'T00:00:00');
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const diffDays = Math.round((eventDate.getTime() - today.getTime()) / 86400000);

    if (diffDays === 0) return 'Today';
    if (diffDays === 1) return 'Tomorrow';
    if (diffDays === -1) return 'Yesterday';
    if (diffDays > 1 && diffDays <= 7) return `In ${diffDays} days`;
    if (diffDays < -1 && diffDays >= -7) return `${Math.abs(diffDays)} days ago`;
    return '';
};