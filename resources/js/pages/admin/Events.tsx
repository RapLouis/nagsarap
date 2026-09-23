import React, { useEffect, useRef, useState } from 'react';
import { Head, Link, router, useForm } from '@inertiajs/react';
import AdminLayout from '@/layouts/admin-layout';
import DeleteModal from '@/components/delete-modal';
import LocationPicker from '@/components/location-picker';
import FormSwitch from '@/components/ui/form-switch';
import {
    Calendar,
    MapPin,
    Plus,
    Search,
    Trash2,
    CheckCircle2,
    AlertCircle,
    X,
    LogIn,
    LogOut,
    Pencil,
    Check,
    XCircle,
    CalendarX,
    Navigation,
    Hexagon,
    CircleDot,
    Loader2,
    ArrowRight,
    ArrowLeft,
    FileText,
} from 'lucide-react';

type TabKey = 'ongoing' | 'upcoming' | 'completed' | 'pending' | 'declined';
type Point = { lat: number; lng: number };

type TimeSlot = {
    time_in_start: string;
    time_in_end: string;
    time_out_start: string;
    time_out_end: string;
};

type ScheduleItem = {
    date: string;
    slots: TimeSlot[];
};

type EventItem = {
    event_id: number;
    title: string;
    description: string | null;
    location: string | null;
    is_geofenced: boolean;
    geofence_type: 'radius' | 'polygon';
    latitude: number | null;
    longitude: number | null;
    radius_meters: number;
    geofence_polygon: Point[] | null;
    event_date: string;
    event_end_date: string | null;
    schedules: ScheduleItem[] | null;
    time_in_start: string;
    time_in_end: string | null;
    time_out_start: string | null;
    time_out_end: string | null;
    approval_status: 'approved' | 'pending' | 'declined';
    is_active: boolean;
};

type PageLink = { url: string | null; label: string; active: boolean };

type Props = {
    events: {
        data: EventItem[];
        links: PageLink[];
    };
    counts?: Record<TabKey, number>;
    filters: { search?: string; tab?: TabKey };
};

const TABS: { key: TabKey; label: string; activeColor: string }[] = [
    { key: 'ongoing', label: 'On Going', activeColor: 'text-blue-600 border-blue-600 bg-blue-50/50' },
    { key: 'upcoming', label: 'Upcoming', activeColor: 'text-emerald-600 border-emerald-600 bg-emerald-50/50' },
    { key: 'completed', label: 'Completed', activeColor: 'text-indigo-900 border-indigo-900 bg-indigo-50/50' },
    { key: 'pending', label: 'Pending Approval', activeColor: 'text-amber-600 border-amber-600 bg-amber-50/50' },
    { key: 'declined', label: 'Declined', activeColor: 'text-rose-600 border-rose-600 bg-rose-50/50' },
];

function relativeDateLabel(dateStr: string): string {
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
}

function formatDate(dateStr: string): string {
    return new Date(dateStr + 'T00:00:00').toLocaleDateString(undefined, {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
    });
}

function getEventDays(startDate: string, endDate: string | null): string[] {
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
}

export default function Events({
    events,
    counts = { ongoing: 0, upcoming: 0, completed: 0, pending: 0, declined: 0 },
    filters,
}: Props) {
    const [search, setSearch] = useState(filters.search || '');
    const [activeTab, setActiveTab] = useState<TabKey>(filters.tab || 'ongoing');
    const [isFiltering, setIsFiltering] = useState(false);
    const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
    const isFirstRun = useRef(true);

    // Wizard Flow States
    const [currentStep, setCurrentStep] = useState<number>(1);
    const [isMultiDay, setIsMultiDay] = useState(false);
    const [scheduleMode, setScheduleMode] = useState<'uniform' | 'custom'>('uniform');
    const [timeValidationError, setTimeValidationError] = useState<string | null>(null);

    // Uniform schedule state
    const [uniformSchedule, setUniformSchedule] = useState<TimeSlot>({
        time_in_start: '08:00',
        time_in_end: '12:00',
        time_out_start: '13:00',
        time_out_end: '17:00',
    });

    // Modal & Alert States
    const [isFormOpen, setIsFormOpen] = useState(false);
    const [editingEvent, setEditingEvent] = useState<EventItem | null>(null);
    const [isDeleteOpen, setIsDeleteOpen] = useState(false);
    const [selectedEvent, setSelectedEvent] = useState<EventItem | null>(null);
    const [isDeleting, setIsDeleting] = useState(false);
    const [successMessage, setSuccessMessage] = useState<string | null>(null);
    const [isSearchingLocation, setIsSearchingLocation] = useState(false);
    const [geocodeConfirmation, setGeocodeConfirmation] = useState<string | null>(null);
    const [quickActionEventId, setQuickActionEventId] = useState<number | null>(null);

    const { data, setData, post, put, processing, errors, reset, clearErrors } = useForm({
        title: '',
        description: '',
        location: '',
        is_geofenced: false,
        geofence_type: 'radius' as 'radius' | 'polygon',
        latitude: 18.1972 as number | null,
        longitude: 120.5928 as number | null,
        radius_meters: 100,
        geofence_polygon: null as Point[] | null,
        event_date: '',
        event_end_date: '' as string | null,
        schedules: [] as ScheduleItem[],
        approval_status: 'approved' as 'approved' | 'pending' | 'declined',
        is_active: true,
    });

    const hasFormErrors = Object.keys(errors).length > 0;

    // Time validation check helper
    const validateTimeSlots = (schedules: ScheduleItem[]): boolean => {
        for (const sched of schedules) {
            for (const slot of sched.slots) {
                if (slot.time_in_start && slot.time_in_end && slot.time_in_start >= slot.time_in_end) {
                    setTimeValidationError(`Conflict on ${sched.date}: Time-In Start must be earlier than Time-In Cutoff.`);
                    return false;
                }
                if (slot.time_in_end && slot.time_out_start && slot.time_in_end >= slot.time_out_start) {
                    setTimeValidationError(`Conflict on ${sched.date}: Time-In Cutoff cannot overlap or be after Time-Out Start.`);
                    return false;
                }
                if (slot.time_out_start && slot.time_out_end && slot.time_out_start >= slot.time_out_end) {
                    setTimeValidationError(`Conflict on ${sched.date}: Time-Out Start must be earlier than Time-Out Cutoff.`);
                    return false;
                }
            }
        }
        setTimeValidationError(null);
        return true;
    };

    // Synchronize schedules automatically when dates, multi-day toggle, or modes change
    useEffect(() => {
        if (!data.event_date) return;
        const days = getEventDays(data.event_date, isMultiDay ? data.event_end_date : null);

        const newSchedules = days.map((day) => {
            const existing = data.schedules.find((s) => s.date === day);
            if (existing) return existing;

            if (scheduleMode === 'uniform' && isMultiDay) {
                return {
                    date: day,
                    slots: [{ ...uniformSchedule }],
                };
            }

            return {
                date: day,
                slots: [
                    {
                        time_in_start: '08:00',
                        time_in_end: '12:00',
                        time_out_start: '13:00',
                        time_out_end: '17:00',
                    },
                ],
            };
        });

        setData('schedules', newSchedules);
        validateTimeSlots(newSchedules);
    }, [data.event_date, data.event_end_date, isMultiDay, scheduleMode, uniformSchedule]);

    const handleUniformChange = (field: keyof TimeSlot, value: string) => {
        const updatedUniform = { ...uniformSchedule, [field]: value };
        setUniformSchedule(updatedUniform);

        if (scheduleMode === 'uniform') {
            const updatedSchedules = data.schedules.map((s) => ({
                ...s,
                slots: s.slots.map((slot) => ({ ...slot, [field]: value })),
            }));
            setData('schedules', updatedSchedules);
            validateTimeSlots(updatedSchedules);
        }
    };

    useEffect(() => {
        if (successMessage) {
            const timer = setTimeout(() => setSuccessMessage(null), 5000);
            return () => clearTimeout(timer);
        }
    }, [successMessage]);

    useEffect(() => {
        if (isFirstRun.current) {
            isFirstRun.current = false;
            return;
        }

        if (debounceRef.current) clearTimeout(debounceRef.current);
        setIsFiltering(true);

        debounceRef.current = setTimeout(() => {
            router.get(
                '/admin/events',
                { search, tab: activeTab },
                {
                    preserveState: true,
                    replace: true,
                    onFinish: () => setIsFiltering(false),
                },
            );
        }, 350);

        return () => {
            if (debounceRef.current) clearTimeout(debounceRef.current);
        };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [search]);

    const geocodeVenueName = async () => {
        if (!data.location || data.location.trim() === '') return;

        setIsSearchingLocation(true);
        setGeocodeConfirmation(null);
        try {
            const response = await fetch(
                `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(data.location)}`,
            );
            const results = await response.json();

            if (results && results.length > 0) {
                const topMatch = results[0];
                const newLat = parseFloat(topMatch.lat);
                const newLng = parseFloat(topMatch.lon);

                const radiusMeters = data.radius_meters || 50;
                const latOffset = radiusMeters / 111111;
                const lngOffset = radiusMeters / (111111 * Math.cos((newLat * Math.PI) / 180));

                const newHexagon: Point[] = [];
                for (let i = 0; i < 6; i++) {
                    const angle = (i * 60 * Math.PI) / 180;
                    newHexagon.push({
                        lat: newLat + latOffset * Math.sin(angle),
                        lng: newLng + lngOffset * Math.cos(angle),
                    });
                }

                setData((prev) => ({
                    ...prev,
                    latitude: newLat,
                    longitude: newLng,
                    geofence_polygon: newHexagon,
                }));

                setGeocodeConfirmation(topMatch.display_name || `${newLat.toFixed(5)}, ${newLng.toFixed(5)}`);
            } else {
                setGeocodeConfirmation(null);
                alert('Location not found. Try adding a city or landmark.');
            }
        } catch (error) {
            console.error('Error fetching venue geocode:', error);
        } finally {
            setIsSearchingLocation(false);
        }
    };

    const handleTabChange = (tabKey: TabKey) => {
        setActiveTab(tabKey);
        setIsFiltering(true);
        router.get(
            '/admin/events',
            { search, tab: tabKey },
            { preserveState: true, replace: true, onFinish: () => setIsFiltering(false) },
        );
    };

    const handleQuickStatusChange = (eventItem: EventItem, newStatus: 'approved' | 'declined') => {
        setQuickActionEventId(eventItem.event_id);
        router.patch(
            `/admin/events/${eventItem.event_id}/status`,
            { approval_status: newStatus },
            {
                preserveScroll: true,
                onSuccess: () => setSuccessMessage(`Event "${eventItem.title}" updated to ${newStatus}.`),
                onFinish: () => setQuickActionEventId(null),
            },
        );
    };

    const openCreateModal = () => {
        setEditingEvent(null);
        reset();
        clearErrors();
        setCurrentStep(1);
        setIsMultiDay(false);
        setScheduleMode('uniform');
        setGeocodeConfirmation(null);
        setTimeValidationError(null);

        setData((prev) => ({
            ...prev,
            approval_status: 'approved',
            is_active: true,
            event_end_date: '',
            schedules: [],
        }));

        setIsFormOpen(true);
    };

    const openEditModal = (eventItem: EventItem) => {
        setEditingEvent(eventItem);
        clearErrors();
        setCurrentStep(1);
        setGeocodeConfirmation(null);
        setTimeValidationError(null);

        const hasMultiDay = Boolean(eventItem.event_end_date && eventItem.event_end_date !== eventItem.event_date);
        setIsMultiDay(hasMultiDay);

        const savedLat =
            eventItem.latitude !== null && eventItem.latitude !== undefined ? Number(eventItem.latitude) : 18.1972;
        const savedLng =
            eventItem.longitude !== null && eventItem.longitude !== undefined ? Number(eventItem.longitude) : 120.5928;

        const defaultSchedules = getEventDays(eventItem.event_date, eventItem.event_end_date).map((day) => ({
            date: day,
            slots: [
                {
                    time_in_start: eventItem.time_in_start || '08:00',
                    time_in_end: eventItem.time_in_end || '',
                    time_out_start: eventItem.time_out_start || '17:00',
                    time_out_end: eventItem.time_out_end || '',
                },
            ],
        }));

        setData({
            title: eventItem.title,
            description: eventItem.description || '',
            location: eventItem.location || '',
            is_geofenced: Boolean(eventItem.is_geofenced),
            geofence_type: eventItem.geofence_type || 'radius',
            latitude: savedLat,
            longitude: savedLng,
            radius_meters: Number(eventItem.radius_meters) || 100,
            geofence_polygon:
                eventItem.geofence_polygon && eventItem.geofence_polygon.length >= 3 ? eventItem.geofence_polygon : null,
            event_date: eventItem.event_date,
            event_end_date: eventItem.event_end_date || '',
            schedules: eventItem.schedules && eventItem.schedules.length > 0 ? eventItem.schedules : defaultSchedules,
            approval_status: eventItem.approval_status || 'approved',
            is_active: Boolean(eventItem.is_active),
        });

        setIsFormOpen(true);
    };

    const handleFormSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        
        if (!validateTimeSlots(data.schedules)) {
            return;
        }

        const submissionData = {
            ...data,
            event_end_date: isMultiDay ? data.event_end_date : null,
        };

        if (editingEvent) {
            put(`/admin/events/${editingEvent.event_id}`, {
                ...submissionData,
                preserveScroll: true,
                onSuccess: () => {
                    setIsFormOpen(false);
                    setSuccessMessage(`Event "${data.title}" updated successfully.`);
                },
            });
        } else {
            post('/admin/events', {
                ...submissionData,
                preserveScroll: true,
                onSuccess: () => {
                    setIsFormOpen(false);
                    reset();
                    setSuccessMessage('New event created successfully.');
                },
            });
        }
    };

    const promptDelete = (eventItem: EventItem) => {
        setSelectedEvent(eventItem);
        setIsDeleteOpen(true);
    };

    const confirmDelete = () => {
        if (!selectedEvent) return;
        setIsDeleting(true);
        router.delete(`/admin/events/${selectedEvent.event_id}`, {
            onSuccess: () => {
                setIsDeleteOpen(false);
                setSuccessMessage(`Event "${selectedEvent.title}" deleted.`);
                setSelectedEvent(null);
            },
            onFinish: () => setIsDeleting(false),
        });
    };

    return (
        <>
            <Head title="Events Management" />

            <div className="p-6 space-y-6">
                {/* SUCCESS BANNER */}
                {successMessage && (
                    <div className="flex items-center justify-between rounded-2xl bg-emerald-50 border border-emerald-200 p-4 text-emerald-800 shadow-xs transition-all">
                        <div className="flex items-center gap-2 text-sm font-semibold">
                            <CheckCircle2 className="h-5 w-5 text-emerald-600 shrink-0" />
                            <span>{successMessage}</span>
                        </div>
                        <button
                            onClick={() => setSuccessMessage(null)}
                            className="rounded-lg p-1 text-emerald-600 hover:bg-emerald-100"
                            aria-label="Dismiss success message"
                        >
                            <X className="h-5 w-5" />
                        </button>
                    </div>
                )}

                {/* HEADER */}
                <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
                    <div>
                        <h2 className="text-2xl font-bold text-gray-800">Events Management</h2>
                        <p className="text-sm text-gray-500">Configure attendance windows and hybrid venue geofencing boundaries</p>
                    </div>

                    <button
                        onClick={openCreateModal}
                        className="inline-flex items-center gap-2 rounded-xl bg-[#1B1F5C] px-5 py-3 text-sm font-bold text-white shadow-xs hover:bg-[#151848] transition active:scale-[0.98]"
                    >
                        <Plus className="h-5 w-5" />
                        <span>Create New Event</span>
                    </button>
                </div>

                {/* TAB NAVIGATION */}
                <div className="border-b border-gray-200 bg-white px-4 rounded-2xl shadow-xs">
                    <nav className="-mb-px flex space-x-6 overflow-x-auto">
                        {TABS.map((tab) => {
                            const isActive = activeTab === tab.key;
                            const count = counts?.[tab.key] ?? 0;
                            return (
                                <button
                                    key={tab.key}
                                    onClick={() => handleTabChange(tab.key)}
                                    className={`whitespace-nowrap py-4 px-3 border-b-2 font-bold text-sm transition-all flex items-center gap-2.5 ${
                                        isActive ? `${tab.activeColor} border-b-2` : 'border-transparent text-gray-400 hover:text-gray-700'
                                    }`}
                                >
                                    <span>{tab.label}</span>
                                    <span
                                        className={`rounded-full px-2.5 py-0.5 text-xs transition-opacity ${
                                            isActive ? 'bg-white shadow-xs text-gray-800' : 'bg-gray-100 text-gray-500'
                                        } ${isFiltering && isActive ? 'opacity-50' : 'opacity-100'}`}
                                    >
                                        {count}
                                    </span>
                                </button>
                            );
                        })}
                    </nav>
                </div>

                {/* SEARCH TOOLBAR */}
                <div className="flex items-center justify-between bg-white p-4 rounded-2xl border border-gray-100 shadow-xs">
                    <div className="relative w-full sm:w-80">
                        <input
                            type="text"
                            placeholder="Search event title, location..."
                            value={search}
                            onChange={(e) => setSearch(e.target.value)}
                            className="w-full pl-10 pr-9 py-2.5 text-sm rounded-xl border border-gray-200 focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                            aria-label="Search events"
                        />
                        {isFiltering ? (
                            <Loader2 className="absolute left-3.5 top-3 h-4 w-4 text-gray-400 animate-spin" />
                        ) : (
                            <Search className="absolute left-3.5 top-3 h-4 w-4 text-gray-400" />
                        )}
                        {search && (
                            <button
                                onClick={() => setSearch('')}
                                className="absolute right-3 top-2.5 rounded-full p-0.5 text-gray-400 hover:bg-gray-100 hover:text-gray-600"
                                aria-label="Clear search"
                            >
                                <X className="h-4 w-4" />
                            </button>
                        )}
                    </div>
                </div>

                {/* EVENTS — DESKTOP TABLE */}
                <div className="hidden sm:block overflow-hidden rounded-2xl border border-gray-100 bg-white shadow-xs">
                    <table className="w-full text-left text-sm text-gray-600">
                        <thead className="bg-gray-50 text-xs font-semibold uppercase text-gray-500">
                            <tr>
                                <th className="px-6 py-4">Event Details</th>
                                <th className="px-6 py-4">Geofence Type</th>
                                <th className="px-6 py-4">Time-In Window</th>
                                <th className="px-6 py-4">Time-Out Window</th>
                                <th className="px-6 py-4">Status</th>
                                <th className="px-6 py-4 text-right">Actions</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-100 text-sm">
                            {events.data.length > 0 ? (
                                events.data.map((item) => {
                                    const relLabel = relativeDateLabel(item.event_date);
                                    const isQuickActing = quickActionEventId === item.event_id;
                                    return (
                                        <tr key={item.event_id} className="hover:bg-gray-50/50 transition-colors">
                                            <td className="px-6 py-4 max-w-[260px]">
                                                <Link href={`/admin/analytics/events/${item.event_id}`} className="block">
                                                    <div className="font-bold text-[#1B1F5C] truncate hover:underline text-base" title={item.title}>
                                                        {item.title}
                                                    </div>
                                                    <div className="flex items-center gap-2 text-xs text-gray-400 mt-1">
                                                        <span>
                                                            {formatDate(item.event_date)}
                                                            {item.event_end_date && item.event_end_date !== item.event_date
                                                                ? ` - ${formatDate(item.event_end_date)}`
                                                                : ''}
                                                        </span>
                                                        {relLabel && (
                                                            <span className="rounded-full bg-gray-100 px-2 py-0.5 text-xs font-semibold text-gray-600">
                                                                {relLabel}
                                                            </span>
                                                        )}
                                                    </div>
                                                </Link>
                                            </td>

                                            <td className="px-6 py-4">
                                                <Link href={`/admin/analytics/events/${item.event_id}`} className="block">
                                                    <div className="flex items-center gap-1.5 font-semibold text-gray-700">
                                                        <MapPin className="h-4 w-4 text-gray-400 shrink-0" />
                                                        <span className="truncate max-w-[160px]" title={item.location || 'Unspecified Venue'}>
                                                            {item.location || 'Unspecified Venue'}
                                                        </span>
                                                    </div>
                                                    {item.is_geofenced ? (
                                                        <span className="inline-flex items-center gap-1.5 text-xs text-blue-600 font-bold mt-1">
                                                            {item.geofence_type === 'polygon' ? (
                                                                <Hexagon className="h-3.5 w-3.5" />
                                                            ) : (
                                                                <CircleDot className="h-3.5 w-3.5" />
                                                            )}
                                                            <span>
                                                                {item.geofence_type === 'polygon' ? 'Hexagon Polygon' : `Radius (${item.radius_meters}m)`}
                                                            </span>
                                                        </span>
                                                    ) : (
                                                        <span className="text-xs text-gray-400 block mt-1">Location Free</span>
                                                    )}
                                                </Link>
                                            </td>

                                            <td className="px-6 py-4 text-gray-600">
                                                <Link href={`/admin/analytics/events/${item.event_id}`} className="block">
                                                    <div className="flex items-center gap-2 font-medium text-emerald-700">
                                                        <LogIn className="h-4 w-4" />
                                                        <span>{item.time_in_start}</span>
                                                        {item.time_in_end && <span className="text-gray-400">- {item.time_in_end}</span>}
                                                    </div>
                                                </Link>
                                            </td>

                                            <td className="px-6 py-4 text-gray-600">
                                                <Link href={`/admin/analytics/events/${item.event_id}`} className="block">
                                                    {item.time_out_start ? (
                                                        <div className="flex items-center gap-2 font-medium text-amber-700">
                                                            <LogOut className="h-4 w-4" />
                                                            <span>{item.time_out_start}</span>
                                                            {item.time_out_end && <span className="text-gray-400">- {item.time_out_end}</span>}
                                                        </div>
                                                    ) : (
                                                        <span className="text-gray-300">Disabled</span>
                                                    )}
                                                </Link>
                                            </td>

                                            <td className="px-6 py-4">
                                                <Link href={`/admin/analytics/events/${item.event_id}`} className="block">
                                                    <span
                                                        className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold ${
                                                            item.is_active ? 'bg-emerald-50 text-emerald-700' : 'bg-gray-100 text-gray-500'
                                                        }`}
                                                    >
                                                        <span className={`h-2 w-2 rounded-full ${item.is_active ? 'bg-emerald-500' : 'bg-gray-400'}`} />
                                                        {item.is_active ? 'Active' : 'Inactive'}
                                                    </span>
                                                </Link>
                                            </td>

                                            <td className="px-6 py-4 text-right">
                                                <div className="flex items-center justify-end gap-1.5">
                                                    {activeTab === 'pending' && (
                                                        <>
                                                            <button
                                                                onClick={() => handleQuickStatusChange(item, 'approved')}
                                                                disabled={isQuickActing}
                                                                className="rounded-lg p-2 text-emerald-600 hover:bg-emerald-50 transition disabled:opacity-40"
                                                                title="Approve Event"
                                                            >
                                                                {isQuickActing ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-5 w-5" />}
                                                            </button>
                                                            <button
                                                                onClick={() => handleQuickStatusChange(item, 'declined')}
                                                                disabled={isQuickActing}
                                                                className="rounded-lg p-2 text-rose-600 hover:bg-rose-50 transition disabled:opacity-40"
                                                                title="Decline Event"
                                                            >
                                                                <XCircle className="h-5 w-5" />
                                                            </button>
                                                        </>
                                                    )}
                                                    <button
                                                        onClick={() => openEditModal(item)}
                                                        className="rounded-lg p-2 text-gray-400 hover:bg-gray-100 hover:text-gray-700 transition"
                                                        title="Edit Event"
                                                    >
                                                        <Pencil className="h-5 w-5" />
                                                    </button>
                                                    <button
                                                        onClick={() => promptDelete(item)}
                                                        className="rounded-lg p-2 text-gray-400 hover:bg-rose-50 hover:text-rose-600 transition"
                                                        title="Delete Event"
                                                    >
                                                        <Trash2 className="h-5 w-5" />
                                                    </button>
                                                </div>
                                            </td>
                                        </tr>
                                    );
                                })
                            ) : (
                                <tr>
                                    <td colSpan={6} className="px-6 py-16 text-center text-gray-400 space-y-3">
                                        <CalendarX className="h-10 w-10 mx-auto text-gray-300" />
                                        <p className="font-semibold text-sm">No {activeTab} events found.</p>
                                    </td>
                                </tr>
                            )}
                        </tbody>
                    </table>
                </div>

                {/* PAGINATION */}
                {events.links.length > 3 && (
                    <nav className="flex flex-wrap items-center justify-center gap-1.5" aria-label="Pagination">
                        {events.links.map((link, idx) => (
                            <Link
                                key={idx}
                                href={link.url ?? '#'}
                                preserveState
                                preserveScroll
                                className={`min-w-[2.25rem] rounded-xl px-3.5 py-2 text-center text-sm font-semibold transition ${
                                    link.active
                                        ? 'bg-[#1B1F5C] text-white'
                                        : link.url
                                        ? 'bg-white text-gray-600 border border-gray-200 hover:bg-gray-50'
                                        : 'bg-white text-gray-300 border border-gray-100 pointer-events-none'
                                }`}
                                dangerouslySetInnerHTML={{ __html: link.label }}
                            />
                        ))}
                    </nav>
                )}
            </div>

            {/* 3-STEP WIZARD FORM MODAL */}
            {isFormOpen && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4 backdrop-blur-xs">
                    <div className="flex w-full max-w-3xl max-h-[92vh] flex-col rounded-3xl bg-white shadow-2xl transition-all">
                        {/* Modal Header */}
                        <div className="flex items-center justify-between border-b border-gray-100 p-6 pb-4">
                            <div className="flex items-center gap-3">
                                <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-[#1B1F5C]/10 text-[#1B1F5C]">
                                    <Calendar className="h-5 w-5" />
                                </div>
                                <div>
                                    <h3 className="text-lg font-bold text-[#0F172A]">
                                        {editingEvent ? 'Edit Event Details' : 'Create New Event'}
                                    </h3>
                                    <p className="text-xs text-gray-400">Step {currentStep} of 3: {
                                        currentStep === 1 ? 'Event Basic Info & Schedule' :
                                        currentStep === 2 ? 'Venue & Geofencing' : 'Review & Confirmation'
                                    }</p>
                                </div>
                            </div>
                            <button
                                onClick={() => setIsFormOpen(false)}
                                className="rounded-lg p-1.5 text-gray-400 hover:bg-gray-100"
                                aria-label="Close"
                            >
                                <X className="h-5 w-5" />
                            </button>
                        </div>

                        {(hasFormErrors || timeValidationError) && (
                            <div className="mx-6 mt-4 flex items-start gap-2.5 rounded-2xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">
                                <AlertCircle className="h-5 w-5 shrink-0 mt-0.5" />
                                <div>
                                    <p className="font-bold">Please fix the following before saving:</p>
                                    <ul className="list-disc list-inside mt-1 space-y-0.5 text-xs">
                                        {timeValidationError && <li>{timeValidationError}</li>}
                                        {Object.values(errors).map((msg, i) => (
                                            <li key={i}>{msg}</li>
                                        ))}
                                    </ul>
                                </div>
                            </div>
                        )}

                        <form id="event-form" onSubmit={handleFormSubmit} className="flex-1 overflow-y-auto px-6 py-4 space-y-5 text-sm">
                            
                            {/* ================= STEP 1: EVENT DETAILS & SCHEDULES ================= */}
                            {currentStep === 1 && (
                                <div className="space-y-4 animate-fadeIn">
                                    <div>
                                        <label htmlFor="event-title" className="block font-bold uppercase tracking-wider text-gray-500 text-xs">
                                            Event Title *
                                        </label>
                                        <input
                                            id="event-title"
                                            type="text"
                                            required
                                            value={data.title}
                                            onChange={(e) => setData('title', e.target.value)}
                                            placeholder="e.g. University Sportsfest"
                                            className="mt-1.5 w-full rounded-xl border border-gray-200 bg-white px-3.5 py-2.5 text-gray-800 text-sm font-medium focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                                        />
                                    </div>

                                    <div>
                                        <label htmlFor="event-description" className="block font-bold uppercase tracking-wider text-gray-500 text-xs">
                                            Description
                                        </label>
                                        <textarea
                                            id="event-description"
                                            rows={2}
                                            value={data.description}
                                            onChange={(e) => setData('description', e.target.value)}
                                            placeholder="Optional details..."
                                            className="mt-1.5 w-full rounded-xl border border-gray-200 bg-white p-3.5 text-gray-800 text-sm font-medium focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                                        />
                                    </div>

                                    {/* Multi-Day Range Toggle */}
                                    <div className="rounded-2xl border border-gray-200 bg-gray-50/50 p-4 space-y-3">
                                        <FormSwitch
                                            checked={isMultiDay}
                                            onCheckedChange={(checked: boolean) => {
                                                setIsMultiDay(checked);
                                                if (!checked) setData('event_end_date', '');
                                            }}
                                            label="Enable Multi-Day Event (Span Range)"
                                        />

                                        <div className={`grid ${isMultiDay ? 'grid-cols-2' : 'grid-cols-1'} gap-3`}>
                                            <div>
                                                <label htmlFor="event-date" className="block font-bold uppercase tracking-wider text-gray-500 text-xs">
                                                    {isMultiDay ? 'Start Date *' : 'Event Date *'}
                                                </label>
                                                <input
                                                    id="event-date"
                                                    type="date"
                                                    required
                                                    value={data.event_date}
                                                    onChange={(e) => setData('event_date', e.target.value)}
                                                    className="mt-1.5 w-full rounded-xl border border-gray-200 bg-white px-3.5 py-2.5 text-gray-800 text-sm font-medium focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                                                />
                                            </div>

                                            {isMultiDay && (
                                                <div>
                                                    <label htmlFor="event-end-date" className="block font-bold uppercase tracking-wider text-gray-500 text-xs">
                                                        End Date *
                                                    </label>
                                                    <input
                                                        id="event-end-date"
                                                        type="date"
                                                        required={isMultiDay}
                                                        min={data.event_date}
                                                        value={data.event_end_date || ''}
                                                        onChange={(e) => setData('event_end_date', e.target.value)}
                                                        className="mt-1.5 w-full rounded-xl border border-gray-200 bg-white px-3.5 py-2.5 text-gray-800 text-sm font-medium focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                                                    />
                                                </div>
                                            )}
                                        </div>
                                    </div>

                                    {/* MULTI-DAY SCHEDULE MODE SELECTOR (Uniform vs Custom) */}
                                    {isMultiDay && (
                                        <div className="rounded-2xl border border-blue-100 bg-blue-50/40 p-4 space-y-3">
                                            <label className="block font-bold text-blue-900 uppercase tracking-wider text-xs">
                                                Multi-Day Schedule Mode
                                            </label>
                                            <div className="grid grid-cols-2 gap-2">
                                                <button
                                                    type="button"
                                                    onClick={() => setScheduleMode('uniform')}
                                                    className={`py-2.5 px-3 rounded-xl font-bold text-xs transition flex items-center justify-center gap-1.5 ${
                                                        scheduleMode === 'uniform'
                                                            ? 'bg-[#1B1F5C] text-white shadow-xs'
                                                            : 'bg-white text-gray-600 border border-gray-200 hover:bg-gray-50'
                                                    }`}
                                                >
                                                    Uniform Schedule (Same Hours Daily)
                                                </button>
                                                <button
                                                    type="button"
                                                    onClick={() => setScheduleMode('custom')}
                                                    className={`py-2.5 px-3 rounded-xl font-bold text-xs transition flex items-center justify-center gap-1.5 ${
                                                        scheduleMode === 'custom'
                                                            ? 'bg-[#1B1F5C] text-white shadow-xs'
                                                            : 'bg-white text-gray-600 border border-gray-200 hover:bg-gray-50'
                                                    }`}
                                                >
                                                    Custom Daily Schedule (Different Hours)
                                                </button>
                                            </div>
                                        </div>
                                    )}

                                    {/* UNIFORM SCHEDULE CONFIG (If Multi-Day + Uniform) */}
                                    {isMultiDay && scheduleMode === 'uniform' && (
                                        <div className="rounded-2xl border border-emerald-100 bg-emerald-50/40 p-4 space-y-3">
                                            <div className="flex items-center gap-2 font-bold text-emerald-800 text-xs">
                                                <Calendar className="h-4 w-4" />
                                                <span>Uniform Hours (Applied to All Days)</span>
                                            </div>

                                            {/* Time-In Row */}
                                            <div className="grid grid-cols-2 gap-3 items-end pt-2 border-t border-emerald-200/50">
                                                <div>
                                                    <label className="block font-bold text-gray-600 text-xs">Time-In Start *</label>
                                                    <input
                                                        type="time"
                                                        required
                                                        value={uniformSchedule.time_in_start}
                                                        onChange={(e) => handleUniformChange('time_in_start', e.target.value)}
                                                        className="mt-1.5 w-full rounded-xl border border-gray-200 bg-white px-3.5 py-2 text-gray-800 text-sm font-medium"
                                                    />
                                                </div>
                                                <div>
                                                    <label className="block font-bold text-gray-600 text-xs">Time-In Cutoff</label>
                                                    <input
                                                        type="time"
                                                        value={uniformSchedule.time_in_end}
                                                        onChange={(e) => handleUniformChange('time_in_end', e.target.value)}
                                                        className="mt-1.5 w-full rounded-xl border border-gray-200 bg-white px-3.5 py-2 text-gray-800 text-sm font-medium"
                                                    />
                                                </div>
                                            </div>

                                            {/* Time-Out Row */}
                                            <div className="grid grid-cols-2 gap-3 items-end pt-2 border-t border-emerald-200/50">
                                                <div>
                                                    <label className="block font-bold text-gray-600 text-xs">Time-Out Start</label>
                                                    <input
                                                        type="time"
                                                        value={uniformSchedule.time_out_start}
                                                        onChange={(e) => handleUniformChange('time_out_start', e.target.value)}
                                                        className="mt-1.5 w-full rounded-xl border border-gray-200 bg-white px-3.5 py-2 text-gray-800 text-sm font-medium"
                                                    />
                                                </div>
                                                <div>
                                                    <label className="block font-bold text-gray-600 text-xs">Time-Out Cutoff</label>
                                                    <input
                                                        type="time"
                                                        value={uniformSchedule.time_out_end}
                                                        onChange={(e) => handleUniformChange('time_out_end', e.target.value)}
                                                        className="mt-1.5 w-full rounded-xl border border-gray-200 bg-white px-3.5 py-2 text-gray-800 text-sm font-medium"
                                                    />
                                                </div>
                                            </div>
                                        </div>
                                    )}

                                    {/* CUSTOM DAILY SCHEDULES OR SINGLE-DAY CONFIG (WITH MULTIPLE SLOTS + ADD BUTTON) */}
                                    {(!isMultiDay || scheduleMode === 'custom') &&
                                        data.schedules.map((schedule, dayIndex) => {
                                            const dayNumber = dayIndex + 1;
                                            return (
                                                <div key={schedule.date} className="rounded-2xl border border-emerald-100 bg-emerald-50/40 p-4 space-y-4">
                                                    <div className="flex items-center justify-between">
                                                        <div className="flex items-center gap-2 font-bold text-emerald-800 text-xs">
                                                            <Calendar className="h-4 w-4" />
                                                            <span>
                                                                {isMultiDay
                                                                    ? `Day ${dayNumber} (${formatDate(schedule.date)}) Schedule`
                                                                    : 'Event Schedule Configuration'}
                                                            </span>
                                                        </div>

                                                        <button
                                                            type="button"
                                                            onClick={() => {
                                                                const updated = [...data.schedules];
                                                                updated[dayIndex].slots.push({
                                                                    time_in_start: '13:00',
                                                                    time_in_end: '13:30',
                                                                    time_out_start: '17:00',
                                                                    time_out_end: '17:30',
                                                                });
                                                                setData('schedules', updated);
                                                                validateTimeSlots(updated);
                                                            }}
                                                            className="inline-flex items-center gap-1 rounded-xl bg-emerald-600 px-3 py-1.5 text-xs font-bold text-white hover:bg-emerald-700 transition"
                                                        >
                                                            <Plus className="h-4 w-4" />
                                                            <span>Add Time Slot</span>
                                                        </button>
                                                    </div>

                                                    {schedule.slots.map((slot, slotIndex) => (
                                                        <div key={slotIndex} className="relative rounded-xl border border-emerald-200 bg-white p-3.5 space-y-3 shadow-2xs">
                                                            {schedule.slots.length > 1 && (
                                                                <button
                                                                    type="button"
                                                                    onClick={() => {
                                                                        const updated = [...data.schedules];
                                                                        updated[dayIndex].slots.splice(slotIndex, 1);
                                                                        setData('schedules', updated);
                                                                        validateTimeSlots(updated);
                                                                    }}
                                                                    className="absolute right-2 top-2 rounded-lg p-1 text-gray-400 hover:bg-rose-50 hover:text-rose-600 transition"
                                                                    title="Remove Slot"
                                                                >
                                                                    <X className="h-4 w-4" />
                                                                </button>
                                                            )}

                                                            <span className="text-xs font-bold uppercase text-emerald-700 tracking-wider block">
                                                                Slot {slotIndex + 1}
                                                            </span>

                                                            {/* Time-In Inputs */}
                                                            <div className="grid grid-cols-2 gap-3 items-end">
                                                                <div>
                                                                    <label className="block font-bold text-gray-600 text-xs">Time-In Start *</label>
                                                                    <input
                                                                        type="time"
                                                                        required
                                                                        value={slot.time_in_start}
                                                                        onChange={(e) => {
                                                                            const updated = [...data.schedules];
                                                                            updated[dayIndex].slots[slotIndex].time_in_start = e.target.value;
                                                                            setData('schedules', updated);
                                                                            validateTimeSlots(updated);
                                                                        }}
                                                                        className="mt-1.5 w-full rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-gray-800 font-medium text-sm"
                                                                    />
                                                                </div>
                                                                <div>
                                                                    <label className="block font-bold text-gray-600 text-xs">Time-In Cutoff</label>
                                                                    <input
                                                                        type="time"
                                                                        value={slot.time_in_end}
                                                                        onChange={(e) => {
                                                                            const updated = [...data.schedules];
                                                                            updated[dayIndex].slots[slotIndex].time_in_end = e.target.value;
                                                                            setData('schedules', updated);
                                                                            validateTimeSlots(updated);
                                                                        }}
                                                                        className="mt-1.5 w-full rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-gray-800 font-medium text-sm"
                                                                    />
                                                                </div>
                                                            </div>

                                                            {/* Time-Out Inputs */}
                                                            <div className="grid grid-cols-2 gap-3 items-end pt-2 border-t border-gray-100">
                                                                <div>
                                                                    <label className="block font-bold text-gray-600 text-xs">Time-Out Start</label>
                                                                    <input
                                                                        type="time"
                                                                        value={slot.time_out_start}
                                                                        onChange={(e) => {
                                                                            const updated = [...data.schedules];
                                                                            updated[dayIndex].slots[slotIndex].time_out_start = e.target.value;
                                                                            setData('schedules', updated);
                                                                            validateTimeSlots(updated);
                                                                        }}
                                                                        className="mt-1.5 w-full rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-gray-800 font-medium text-sm"
                                                                    />
                                                                </div>
                                                                <div>
                                                                    <label className="block font-bold text-gray-600 text-xs">Time-Out Cutoff</label>
                                                                    <input
                                                                        type="time"
                                                                        value={slot.time_out_end}
                                                                        onChange={(e) => {
                                                                            const updated = [...data.schedules];
                                                                            updated[dayIndex].slots[slotIndex].time_out_end = e.target.value;
                                                                            setData('schedules', updated);
                                                                            validateTimeSlots(updated);
                                                                        }}
                                                                        className="mt-1.5 w-full rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-gray-800 font-medium text-sm"
                                                                    />
                                                                </div>
                                                            </div>
                                                        </div>
                                                    ))}
                                                </div>
                                            );
                                        })}
                                </div>
                            )}

                            {/* ================= STEP 2: VENUE & GEOFENCING ================= */}
                            {currentStep === 2 && (
                                <div className="space-y-4 animate-fadeIn">
                                    <div>
                                        <label htmlFor="event-location" className="block font-bold uppercase tracking-wider text-gray-500 text-xs">
                                            Venue Name
                                        </label>
                                        <div className="mt-1.5 flex items-center gap-2">
                                            <input
                                                id="event-location"
                                                type="text"
                                                value={data.location}
                                                onChange={(e) => {
                                                    setData('location', e.target.value);
                                                    setGeocodeConfirmation(null);
                                                }}
                                                onKeyDown={(e) => {
                                                    if (e.key === 'Enter') {
                                                        e.preventDefault();
                                                        geocodeVenueName();
                                                    }
                                                }}
                                                placeholder="e.g. MMSU Main Gym"
                                                className="w-full rounded-xl border border-gray-200 bg-white px-3.5 py-2.5 text-gray-800 text-sm font-medium focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                                            />
                                            <button
                                                type="button"
                                                onClick={geocodeVenueName}
                                                disabled={isSearchingLocation}
                                                className="rounded-xl bg-blue-50 border border-blue-200 p-2.5 text-blue-700 hover:bg-blue-100 font-bold transition shrink-0"
                                                title="Locate Venue on Map"
                                            >
                                                {isSearchingLocation ? (
                                                    <Loader2 className="h-5 w-5 animate-spin text-blue-600" />
                                                ) : (
                                                    <Search className="h-5 w-5" />
                                                )}
                                            </button>
                                        </div>
                                        {geocodeConfirmation && (
                                            <p className="mt-1.5 flex items-center gap-1.5 text-xs text-emerald-600 font-semibold">
                                                <CheckCircle2 className="h-4 w-4 shrink-0" />
                                                <span className="truncate">Matched: {geocodeConfirmation}</span>
                                            </p>
                                        )}
                                    </div>

                                    {/* GEOFENCE CONFIGURATION */}
                                    <div className="rounded-2xl border border-blue-100 bg-blue-50/30 p-4 space-y-3">
                                        <div className="flex items-center justify-between">
                                            <div className="flex items-center gap-2 font-bold text-blue-900 text-xs">
                                                <Navigation className="h-4 w-4" />
                                                <span>GPS Geofence Location Boundary</span>
                                            </div>
                                            <FormSwitch
                                                checked={data.is_geofenced}
                                                onCheckedChange={(checked: boolean) => setData('is_geofenced', checked)}
                                                label="Enforce Geofence"
                                                activeClass="peer-checked:bg-blue-600"
                                            />
                                        </div>

                                        {data.is_geofenced && (
                                            <div className="space-y-3 pt-2 border-t border-blue-100">
                                                <div className="grid grid-cols-2 gap-2 bg-blue-100/50 p-1.5 rounded-xl">
                                                    <button
                                                        type="button"
                                                        onClick={() => setData('geofence_type', 'radius')}
                                                        className={`py-2 rounded-lg font-bold text-xs transition flex items-center justify-center gap-1.5 ${
                                                            data.geofence_type === 'radius'
                                                                ? 'bg-white text-blue-900 shadow-xs'
                                                                : 'text-gray-500 hover:text-gray-800'
                                                        }`}
                                                    >
                                                        <CircleDot className="h-4 w-4" />
                                                        <span>Circular Radius</span>
                                                    </button>
                                                    <button
                                                        type="button"
                                                        onClick={() => setData('geofence_type', 'polygon')}
                                                        className={`py-2 rounded-lg font-bold text-xs transition flex items-center justify-center gap-1.5 ${
                                                            data.geofence_type === 'polygon'
                                                                ? 'bg-white text-blue-900 shadow-xs'
                                                                : 'text-gray-500 hover:text-gray-800'
                                                        }`}
                                                    >
                                                        <Hexagon className="h-4 w-4" />
                                                        <span>Hexagon Area</span>
                                                    </button>
                                                </div>

                                                {data.geofence_type === 'radius' && (
                                                    <div>
                                                        <div className="flex items-center justify-between text-xs font-bold text-gray-600 mb-1.5">
                                                            <span>Check-In Radius:</span>
                                                            <span className="text-blue-700">{data.radius_meters} meters</span>
                                                        </div>
                                                        <input
                                                            type="range"
                                                            min={20}
                                                            max={500}
                                                            step={10}
                                                            value={data.radius_meters}
                                                            onChange={(e) => setData('radius_meters', parseInt(e.target.value))}
                                                            className="w-full accent-[#1B1F5C]"
                                                        />
                                                    </div>
                                                )}

                                                <LocationPicker
                                                    mode={data.geofence_type}
                                                    latitude={data.latitude}
                                                    longitude={data.longitude}
                                                    radius={data.radius_meters}
                                                    polygon={data.geofence_polygon}
                                                    onChangeRadius={(lat, lng) => setData((prev) => ({ ...prev, latitude: lat, longitude: lng }))}
                                                    onChangePolygon={(points) => setData('geofence_polygon', points)}
                                                />
                                            </div>
                                        )}
                                    </div>
                                </div>
                            )}

                            {/* ================= STEP 3: REVIEW & CONFIRMATION ================= */}
                            {currentStep === 3 && (
                                <div className="space-y-4 animate-fadeIn">
                                    <div className="rounded-2xl border border-gray-200 bg-gray-50 p-4 space-y-3">
                                        <div className="flex items-center gap-2 font-bold text-[#1B1F5C] text-sm">
                                            <FileText className="h-4 w-4" />
                                            <span>Event Configuration Summary ({data.schedules.length} {data.schedules.length === 1 ? 'Day' : 'Days'})</span>
                                        </div>

                                        <div className="grid grid-cols-2 gap-4 text-sm pt-2 border-t border-gray-200">
                                            <div>
                                                <span className="text-gray-400 block font-bold uppercase tracking-wider text-xs">Title</span>
                                                <p className="font-bold text-gray-800 mt-1">{data.title || 'Untitled Event'}</p>
                                            </div>
                                            <div>
                                                <span className="text-gray-400 block font-bold uppercase tracking-wider text-xs">Date Span</span>
                                                <p className="font-bold text-gray-800 mt-1">
                                                    {data.event_date ? formatDate(data.event_date) : 'Not set'}
                                                    {data.event_end_date && data.event_end_date !== data.event_date
                                                        ? ` to ${formatDate(data.event_end_date)}`
                                                        : ''}
                                                </p>
                                            </div>
                                            <div>
                                                <span className="text-gray-400 block font-bold uppercase tracking-wider text-xs">Venue</span>
                                                <p className="font-bold text-gray-800 mt-1">{data.location || 'Unspecified Venue'}</p>
                                            </div>
                                            <div>
                                                <span className="text-gray-400 block font-bold uppercase tracking-wider text-xs">Geofence</span>
                                                <p className="font-bold text-gray-800 mt-1">
                                                    {data.is_geofenced ? `Enforced (${data.geofence_type})` : 'Disabled'}
                                                </p>
                                            </div>
                                        </div>
                                    </div>

                                    <FormSwitch
                                        checked={data.is_active}
                                        onCheckedChange={(checked: boolean) => setData('is_active', checked)}
                                        label="Set Event as Active Immediately"
                                    />
                                </div>
                            )}
                        </form>

                        {/* WIZARD FOOTER NAVIGATION */}
                        <div className="flex items-center justify-between border-t border-gray-100 p-6 pt-4">
                            <div>
                                {currentStep > 1 && (
                                    <button
                                        type="button"
                                        onClick={() => setCurrentStep(currentStep - 1)}
                                        className="inline-flex items-center gap-1.5 rounded-xl border border-gray-200 px-4 py-2.5 font-bold text-gray-600 hover:bg-gray-50 text-sm"
                                    >
                                        <ArrowLeft className="h-4 w-4" />
                                        <span>Back</span>
                                    </button>
                                )}
                            </div>

                            <div className="flex items-center gap-2">
                                <button
                                    type="button"
                                    onClick={() => setIsFormOpen(false)}
                                    className="rounded-xl border border-gray-200 px-4 py-2.5 font-bold text-gray-600 hover:bg-gray-50 text-sm"
                                >
                                    Cancel
                                </button>

                                {currentStep < 3 ? (
                                    <button
                                        type="button"
                                        onClick={() => setCurrentStep(currentStep + 1)}
                                        className="inline-flex items-center gap-1.5 rounded-xl bg-[#1B1F5C] px-5 py-2.5 font-bold text-white hover:bg-[#151848] text-sm"
                                    >
                                        <span>Next Step</span>
                                        <ArrowRight className="h-4 w-4" />
                                    </button>
                                ) : (
                                    <button
                                        type="submit"
                                        form="event-form"
                                        disabled={processing || Boolean(timeValidationError)}
                                        className="rounded-xl bg-[#1B1F5C] px-5 py-2.5 font-bold text-white hover:bg-[#151848] disabled:opacity-50 text-sm"
                                    >
                                        {processing ? 'Saving...' : editingEvent ? 'Save Changes' : 'Create Event'}
                                    </button>
                                )}
                            </div>
                        </div>
                    </div>
                </div>
            )}

            <DeleteModal
                isOpen={isDeleteOpen}
                title="Delete Event"
                message={`Are you sure you want to delete "${selectedEvent?.title}"?`}
                onClose={() => setIsDeleteOpen(false)}
                onConfirm={confirmDelete}
                isDeleting={isDeleting}
            />
        </>
    );
}

Events.layout = (page: React.ReactNode) => <AdminLayout title="Events Management">{page}</AdminLayout>;