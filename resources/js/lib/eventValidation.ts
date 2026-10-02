export type TimeSlot = {
    time_in_start: string;
    time_in_end: string;
    time_out_start: string;
    time_out_end: string;
};

export type ScheduleItem = {
    date: string;
    slots: TimeSlot[];
};

/**
 * Validates schedule time slots to ensure chronological sequence and prevent overlaps.
 */
export const validateTimeSlots = (
    schedules: ScheduleItem[],
    setErrorCallback: (errorMsg: string | null) => void
): boolean => {
    for (const sched of schedules) {
        for (const slot of sched.slots) {
            if (slot.time_in_start && slot.time_in_end && slot.time_in_start >= slot.time_in_end) {
                setErrorCallback(`Conflict on ${sched.date}: Time-In Start must be earlier than Time-In Cutoff.`);
                return false;
            }
            if (slot.time_in_end && slot.time_out_start && slot.time_in_end >= slot.time_out_start) {
                setErrorCallback(`Conflict on ${sched.date}: Time-In Cutoff cannot overlap or be after Time-Out Start.`);
                return false;
            }
            if (slot.time_out_start && slot.time_out_end && slot.time_out_start >= slot.time_out_end) {
                setErrorCallback(`Conflict on ${sched.date}: Time-Out Start must be earlier than Time-Out Cutoff.`);
                return false;
            }
        }
    }
    setErrorCallback(null);
    return true;
};

/**
 * Checks if the current browser system time falls within any 
 * time-in or time-out slot configured for today's event schedule.
 */
export const isEventWindowOpen = (schedules: ScheduleItem[] | null | undefined): boolean => {
    if (!schedules || schedules.length === 0) return false;

    const now = new Date();
    const todayStr = now.toISOString().split('T')[0]; // YYYY-MM-DD

    // Find the schedule/item matching today's date
    const todaySchedule = schedules.find((sched) => sched.date === todayStr);

    if (!todaySchedule || !todaySchedule.slots || todaySchedule.slots.length === 0) {
        return false;
    }

    const currentHours = String(now.getHours()).padStart(2, '0');
    const currentMinutes = String(now.getMinutes()).padStart(2, '0');
    const currentTime = `${currentHours}:${currentMinutes}`;

    // Loop through all slots for today to check if current time is within any window
    return todaySchedule.slots.some((slot) => {
        const timeInStart = slot.time_in_start;
        const timeInEnd = slot.time_in_end;
        const timeOutStart = slot.time_out_start;
        const timeOutEnd = slot.time_out_end;

        // 1. Evaluate Time-In Window
        let timeInOpen = false;
        if (timeInStart) {
            if (timeInEnd) {
                timeInOpen = currentTime >= timeInStart && currentTime <= timeInEnd;
            } else {
                timeInOpen = currentTime >= timeInStart;
            }
        }

        // 2. Evaluate Time-Out Window
        let timeOutOpen = false;
        if (timeOutStart) {
            if (timeOutEnd) {
                timeOutOpen = currentTime >= timeOutStart && currentTime <= timeOutEnd;
            } else {
                timeOutOpen = currentTime >= timeOutStart;
            }
        }

        return timeInOpen || timeOutOpen;
    });
};

/**
 * Helper to generate an array of sequential date strings between start and end date.
 */
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

/**
 * Format string date into a readable format.
 */
export const formatDate = (dateStr: string): string => {
    return new Date(dateStr + 'T00:00:00').toLocaleDateString(undefined, {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
    });
};

/**
 * Get relative day label (Today, Tomorrow, etc.).
 */
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