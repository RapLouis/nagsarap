import React, { useEffect, useRef, useState } from 'react';
import { Head, Link, router, useForm } from '@inertiajs/react';
import AdminLayout from '@/layouts/admin-layout';
import DeleteModal from '@/components/delete-modal';
import LocationPicker from '@/components/location-picker';
import FormSwitch from '@/components/ui/form-switch';
import { formatAMPM } from '@/lib/timeUtils';
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
    Copy,
    Building2,
    CheckSquare,
    Square,
    Sun,
    Sunset,
} from 'lucide-react';
import { 
    validateTimeSlots, 
    getEventDays, 
    formatDate, 
    relativeDateLabel 
} from '@/lib/eventValidation';

type TabKey = 'ongoing' | 'upcoming' | 'completed' | 'pending' | 'declined';
type Point = { lat: number; lng: number };

type CheckpointSlot = {
    has_afternoon?: boolean;
    morning_time_in_start?: string;
    morning_time_in_end?: string;
    morning_time_out_start?: string;
    morning_time_out_end?: string;
    afternoon_time_in_start?: string;
    afternoon_time_in_end?: string;
    afternoon_time_out_start?: string;
    afternoon_time_out_end?: string;
    [key: string]: string | boolean | undefined;
};

type ScheduleItem = {
    date: string;
    slots: CheckpointSlot[];
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
    target_scope: 'all' | 'section';
    target_sections: string[] | null;
    event_date: string;
    event_end_date: string | null;
    schedules: ScheduleItem[] | null;
    approval_status: 'approved' | 'pending' | 'declined';
    is_active: boolean;
    attendance_count?: number;
    target_headcount?: number;
};

type VenueItem = {
    location: string;
    latitude: number | null;
    longitude: number | null;
    radius_meters: number;
};

type PageLink = { url: string | null; label: string; active: boolean };

type Props = {
    events: {
        data: EventItem[];
        links: PageLink[];
    };
    counts?: Record<TabKey, number>;
    venues?: VenueItem[];
    availableSections?: string[];
    filters: { search?: string; tab?: TabKey };
};

const TABS: { key: TabKey; label: string; activeColor: string }[] = [
    { key: 'ongoing', label: 'On Going', activeColor: 'text-[#1B1F5C] border-[#1B1F5C] bg-indigo-50/60' },
    { key: 'upcoming', label: 'Upcoming', activeColor: 'text-emerald-700 border-emerald-600 bg-emerald-50/60' },
    { key: 'completed', label: 'Completed', activeColor: 'text-[#1B1F5C] border-[#1B1F5C] bg-indigo-50/60' },
    { key: 'pending', label: 'Pending Approval', activeColor: 'text-amber-700 border-amber-600 bg-amber-50/60' },
    { key: 'declined', label: 'Declined', activeColor: 'text-rose-700 border-rose-600 bg-rose-50/60' },
];

const DEFAULT_SLOT: CheckpointSlot = {
    has_afternoon: false,
    morning_time_in_start: '08:00',
    morning_time_in_end: '08:30',
    morning_time_out_start: '11:30',
    morning_time_out_end: '12:00',
    afternoon_time_in_start: '13:00',
    afternoon_time_in_end: '13:30',
    afternoon_time_out_start: '16:30',
    afternoon_time_out_end: '17:00',
};

export default function Events({
    events,
    counts = { ongoing: 0, upcoming: 0, completed: 0, pending: 0, declined: 0 },
    venues = [],
    availableSections = [],
    filters,
}: Props) {
    const [search, setSearch] = useState(filters.search || '');
    const [activeTab, setActiveTab] = useState<TabKey>(filters.tab || 'ongoing');
    const [isFiltering, setIsFiltering] = useState(false);
    const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
    const isFirstRun = useRef(true);
    const isEditingLoad = useRef(false);

    // Wizard Flow States
    const [currentStep, setCurrentStep] = useState<number>(1);
    const [isMultiDay, setIsMultiDay] = useState(false);
    const [scheduleMode, setScheduleMode] = useState<'uniform' | 'custom'>('uniform');
    const [timeValidationError, setTimeValidationError] = useState<string | null>(null);

    // Uniform schedule state
    const [uniformSchedule, setUniformSchedule] = useState<CheckpointSlot>(DEFAULT_SLOT);

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
        target_scope: 'all' as 'all' | 'section',
        target_sections: [] as string[],
        event_date: '',
        event_end_date: '' as string | null,
        schedules: [] as ScheduleItem[],
        approval_status: 'approved' as 'approved' | 'pending' | 'declined',
        is_active: true,
    });

    const hasFormErrors = Object.keys(errors).length > 0;

    useEffect(() => {
        if (!data.event_date) return;

        if (isEditingLoad.current) {
            isEditingLoad.current = false;
            return;
        }

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
                slots: [{ ...DEFAULT_SLOT }],
            };
        });

        setData('schedules', newSchedules);
        validateTimeSlots(newSchedules as any, setTimeValidationError);
    }, [data.event_date, data.event_end_date, isMultiDay, scheduleMode, uniformSchedule]);

    const handleUniformChange = (field: string, value: string | boolean) => {
        const updatedUniform = { ...uniformSchedule, [field]: value };
        setUniformSchedule(updatedUniform);

        if (scheduleMode === 'uniform') {
            const updatedSchedules = data.schedules.map((s) => ({
                ...s,
                slots: s.slots.map((slot) => ({ ...slot, [field]: value })),
            }));
            setData('schedules', updatedSchedules);
            validateTimeSlots(updatedSchedules as any, setTimeValidationError);
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
    }, [search]);

    const geocodeVenueName = async (queryLocation?: string) => {
        const targetLocation = queryLocation || data.location;
        if (!targetLocation || targetLocation.trim() === '') return;

        setIsSearchingLocation(true);
        setGeocodeConfirmation(null);
        try {
            const response = await fetch(
                `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(targetLocation)}`,
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
                    location: targetLocation,
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

    const handleApplyVenuePreset = (venue: VenueItem) => {
        setData((prev) => ({
            ...prev,
            location: venue.location,
            latitude: venue.latitude !== null ? Number(venue.latitude) : prev.latitude,
            longitude: venue.longitude !== null ? Number(venue.longitude) : prev.longitude,
            radius_meters: venue.radius_meters ? Number(venue.radius_meters) : prev.radius_meters,
        }));
        setGeocodeConfirmation(venue.location);
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
        isEditingLoad.current = false;
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
            target_scope: 'all',
            target_sections: [],
        }));

        setIsFormOpen(true);
    };

    const openEditModal = (eventItem: EventItem, isClone = false) => {
        isEditingLoad.current = true;
        const clonedEvent = structuredClone(eventItem);

        if (isClone) {
            setEditingEvent(null);
        } else {
            setEditingEvent(clonedEvent);
        }
        clearErrors();
        setCurrentStep(1);
        setGeocodeConfirmation(null);
        setTimeValidationError(null);

        const hasMultiDay = Boolean(clonedEvent.event_end_date && clonedEvent.event_end_date !== clonedEvent.event_date);
        setIsMultiDay(hasMultiDay);

        const savedLat = clonedEvent.latitude !== null && clonedEvent.latitude !== undefined ? Number(clonedEvent.latitude) : 18.1972;
        const savedLng = clonedEvent.longitude !== null && clonedEvent.longitude !== undefined ? Number(clonedEvent.longitude) : 120.5928;

        const hasExistingSchedules = clonedEvent.schedules && clonedEvent.schedules.length > 0;

        const mappedSchedules = hasExistingSchedules
            ? clonedEvent.schedules!.map((sch) => ({
                date: sch.date,
                slots: sch.slots && sch.slots.length > 0 ? sch.slots.map(s => ({
                    ...DEFAULT_SLOT,
                    ...s,
                    has_afternoon: Boolean(s.has_afternoon)
                })) : [{ ...DEFAULT_SLOT }],
            }))
            : getEventDays(clonedEvent.event_date, clonedEvent.event_end_date).map((day) => ({
                date: day,
                slots: [{ ...DEFAULT_SLOT }],
            }));

        const containsMultipleSlots = mappedSchedules.some(s => s.slots && s.slots.length > 1);
        if (containsMultipleSlots || (hasMultiDay && mappedSchedules.length > 1)) {
            setScheduleMode('custom');
        } else {
            setScheduleMode('uniform');
        }

        setData({
            title: isClone ? `${clonedEvent.title} (Copy)` : clonedEvent.title,
            description: clonedEvent.description || '',
            location: clonedEvent.location || '',
            is_geofenced: Boolean(clonedEvent.is_geofenced),
            geofence_type: clonedEvent.geofence_type || 'radius',
            latitude: savedLat,
            longitude: savedLng,
            radius_meters: Number(clonedEvent.radius_meters) || 100,
            geofence_polygon: clonedEvent.geofence_polygon && clonedEvent.geofence_polygon.length >= 3 ? clonedEvent.geofence_polygon : null,
            target_scope: clonedEvent.target_scope || 'all',
            target_sections: clonedEvent.target_sections || [],
            event_date: isClone ? '' : clonedEvent.event_date,
            event_end_date: isClone ? '' : (clonedEvent.event_end_date || ''),
            schedules: isClone ? [] : mappedSchedules,
            approval_status: clonedEvent.approval_status || 'approved',
            is_active: Boolean(clonedEvent.is_active),
        });

        setIsFormOpen(true);
    };

    const handleFormSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        
        if (!validateTimeSlots(data.schedules as any, setTimeValidationError)) {
            return;
        }

        const submissionData = {
            ...data,
            event_end_date: isMultiDay ? data.event_end_date : null,
        };

        if (editingEvent) {
            setData(submissionData);
            put(`/admin/events/${editingEvent.event_id}`, {
                preserveScroll: true,
                onSuccess: () => {
                    setIsFormOpen(false);
                    setSuccessMessage(`Event "${data.title}" updated successfully.`);
                },
            });
        } else {
            setData(submissionData);
            post('/admin/events', {
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
            <Head title="Events Management | 4ttend Attendance System" />

            <div className="p-3 sm:p-5 space-y-4 font-sans text-gray-900 antialiased bg-[#F5F6FA] min-h-screen">
                {successMessage && (
                    <div className="flex items-center justify-between rounded-2xl bg-emerald-50 border border-emerald-200 p-4 text-emerald-800 shadow-xs" role="alert">
                        <div className="flex items-center gap-2.5 text-xs sm:text-sm font-bold">
                            <CheckCircle2 className="h-5 w-5 text-emerald-600 shrink-0" aria-hidden="true" />
                            <span>{successMessage}</span>
                        </div>
                        <button
                            onClick={() => setSuccessMessage(null)}
                            className="rounded-lg p-1 text-emerald-600 hover:bg-emerald-100 focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                            aria-label="Dismiss success notification"
                        >
                            <X className="h-5 w-5" />
                        </button>
                    </div>
                )}

                {/* PAGE HEADER */}
                <header className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 bg-white p-4 sm:p-5 rounded-2xl border border-gray-200/80 shadow-xs">
                    <div className="space-y-0.5">
                        <h1 className="text-xl sm:text-2xl font-black text-[#1B1F5C] tracking-tight">Events Management</h1>
                        <p className="text-xs text-gray-500 font-medium">Configure session checkpoints with start-to-cutoff time ranges and optional afternoon blocks</p>
                    </div>

                    <button
                        onClick={openCreateModal}
                        className="inline-flex items-center justify-center gap-2 min-h-[44px] rounded-xl bg-[#1B1F5C] px-4 py-2.5 text-xs font-bold text-white shadow-md hover:bg-[#131644] focus-visible:ring-2 focus-visible:ring-[#F5A623] transition-all shrink-0 active:scale-98"
                    >
                        <Plus className="h-4.5 w-4.5 text-[#F5A623]" aria-hidden="true" />
                        <span>Create New Event</span>
                    </button>
                </header>

                {/* TABS NAVIGATION */}
                <nav className="border border-gray-200/80 bg-white px-3 sm:px-4 rounded-2xl shadow-xs" aria-label="Events status filter tabs">
                    <div className="-mb-px flex space-x-3 sm:space-x-6 overflow-x-auto">
                        {TABS.map((tab) => {
                            const isActive = activeTab === tab.key;
                            const count = counts?.[tab.key] ?? 0;
                            return (
                                <button
                                    key={tab.key}
                                    onClick={() => handleTabChange(tab.key)}
                                    className={`whitespace-nowrap py-3.5 px-3 border-b-2 font-bold text-xs sm:text-sm transition-all flex items-center gap-2 focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                        isActive ? `${tab.activeColor} border-b-2` : 'border-transparent text-gray-500 hover:text-[#1B1F5C]'
                                    }`}
                                >
                                    <span>{tab.label}</span>
                                    <span
                                        className={`rounded-full px-2.5 py-0.5 text-[10px] sm:text-xs font-bold transition-opacity ${
                                            isActive ? 'bg-white shadow-xs text-[#1B1F5C]' : 'bg-gray-100 text-gray-600'
                                        } ${isFiltering && isActive ? 'opacity-50' : 'opacity-100'}`}
                                    >
                                        {count}
                                    </span>
                                </button>
                            );
                        })}
                    </div>
                </nav>

                {/* TOOLBAR SEARCH */}
                <div className="flex items-center justify-between bg-white p-3.5 sm:p-4 rounded-2xl border border-gray-200/80 shadow-xs">
                    <div className="relative w-full sm:w-80">
                        <input
                            type="text"
                            placeholder="Search event title, location..."
                            value={search}
                            onChange={(e) => setSearch(e.target.value)}
                            className="w-full min-h-[44px] pl-10 pr-9 py-2 text-xs sm:text-sm rounded-xl border border-gray-300 bg-white text-gray-900 placeholder:text-gray-400 focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] focus-visible:outline-none shadow-xs"
                            aria-label="Search events"
                        />
                        {isFiltering ? (
                            <Loader2 className="absolute left-3.5 top-3.5 h-4 w-4 text-gray-400 animate-spin" aria-hidden="true" />
                        ) : (
                            <Search className="absolute left-3.5 top-3.5 h-4 w-4 text-gray-400" aria-hidden="true" />
                        )}
                        {search && (
                            <button
                                onClick={() => setSearch('')}
                                className="absolute right-3 top-3 rounded-full p-0.5 text-gray-400 hover:bg-gray-100 hover:text-gray-600 focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                aria-label="Clear search"
                            >
                                <X className="h-4 w-4" />
                            </button>
                        )}
                    </div>
                </div>

                {/* EVENTS DATA TABLE */}
                <main className="overflow-hidden rounded-2xl border border-gray-200/80 bg-white shadow-xs">
                    <div className="overflow-x-auto">
                        <table className="w-full text-left text-xs sm:text-sm text-gray-700">
                            <thead className="bg-gray-50/80 text-[10px] font-extrabold uppercase tracking-wider text-gray-500 border-b border-gray-100">
                                <tr>
                                    <th className="px-4 sm:px-6 py-3.5">Event Details</th>
                                    <th className="px-4 sm:px-6 py-3.5">Target Audience</th>
                                    <th className="px-4 sm:px-6 py-3.5">Venue & Geofence</th>
                                    <th className="px-4 sm:px-6 py-3.5">Morning Checkpoints</th>
                                    <th className="px-4 sm:px-6 py-3.5">Afternoon Checkpoints</th>
                                    <th className="px-4 sm:px-6 py-3.5">Status</th>
                                    <th className="px-4 sm:px-6 py-3.5 text-right">Actions</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-100 text-xs sm:text-sm" aria-live="polite">
                                {events.data.length > 0 ? (
                                    events.data.map((item) => {
                                        const relLabel = relativeDateLabel(item.event_date);
                                        const isQuickActing = quickActionEventId === item.event_id;
                                        const slot = item?.schedules?.[0]?.slots?.[0];
                                        const hasAfternoon = Boolean(slot?.has_afternoon);
                                        return (
                                            <tr key={item.event_id} className="hover:bg-gray-50/50 transition-colors">
                                                {/* 1. Event Details */}
                                                <td className="px-4 sm:px-6 py-4 max-w-[240px]">
                                                    <Link href={`/admin/analytics/events/${item.event_id}`} className="block group">
                                                        <div className="font-extrabold text-[#1B1F5C] truncate group-hover:underline text-sm sm:text-base" title={item.title}>
                                                            {item.title}
                                                        </div>
                                                        <div className="flex items-center gap-2 text-xs text-gray-500 font-medium mt-1">
                                                            <span>
                                                                {formatDate(item.event_date)}
                                                                {item.event_end_date && item.event_end_date !== item.event_date
                                                                    ? ` - ${formatDate(item.event_end_date)}`
                                                                    : ''}
                                                            </span>
                                                            {relLabel && (
                                                                <span className="rounded-full bg-gray-100 px-2 py-0.5 text-[10px] font-bold text-gray-600">
                                                                    {relLabel}
                                                                </span>
                                                            )}
                                                        </div>
                                                    </Link>
                                                </td>

                                                {/* 2. Target Audience */}
                                                <td className="px-4 sm:px-6 py-4">
                                                    <span className="inline-flex items-center gap-1.5 rounded-xl bg-indigo-50 px-3 py-1.5 text-xs font-bold text-[#1B1F5C] border border-indigo-100">
                                                        <span>
                                                            {item.target_scope === 'all' ? 'All Students' : `${item.target_sections?.length || 0} Section(s)`}
                                                        </span>
                                                    </span>
                                                </td>

                                                {/* 3. Venue & Geofence */}
                                                <td className="px-4 sm:px-6 py-4">
                                                    <Link href={`/admin/analytics/events/${item.event_id}`} className="block">
                                                        <div className="flex items-center gap-1.5 font-bold text-gray-900">
                                                            <MapPin className="h-4 w-4 text-[#F5A623] shrink-0" aria-hidden="true" />
                                                            <span className="truncate max-w-[140px]" title={item.location || 'Unspecified Venue'}>
                                                                {item.location || 'Unspecified Venue'}
                                                            </span>
                                                        </div>
                                                        {item.is_geofenced ? (
                                                            <span className="inline-flex items-center gap-1.5 text-[11px] text-[#1B1F5C] font-bold mt-1">
                                                                {item.geofence_type === 'polygon' ? (
                                                                    <Hexagon className="h-3.5 w-3.5 text-[#F5A623]" aria-hidden="true" />
                                                                ) : (
                                                                    <CircleDot className="h-3.5 w-3.5 text-[#F5A623]" aria-hidden="true" />
                                                                )}
                                                                <span>
                                                                    {item.geofence_type === 'polygon' ? 'Hexagon Boundary' : `Radius (${item.radius_meters}m)`}
                                                                </span>
                                                            </span>
                                                        ) : (
                                                            <span className="text-[11px] text-gray-400 block mt-1 font-medium">Location Free</span>
                                                        )}
                                                    </Link>
                                                </td>
                                                
                                                {/* 4. Morning Checkpoints */}
                                                <td className="px-4 sm:px-6 py-4 text-gray-700">
                                                    <Link href={`/admin/analytics/events/${item.event_id}`} className="block space-y-1">
                                                        <div className="flex items-center gap-1.5 text-xs font-bold text-blue-700" title="Morning Time-In">
                                                            <LogIn className="h-3 w-3 shrink-0 text-blue-600" />
                                                            <span>In: {formatAMPM(typeof slot?.morning_time_in_start === 'string' ? slot.morning_time_in_start : typeof slot?.time_in_start === 'string' ? slot.time_in_start : undefined)}</span>
                                                        </div>
                                                        <div className="flex items-center gap-1.5 text-xs font-semibold text-indigo-700" title="Morning Time-Out">
                                                            <LogOut className="h-3 w-3 shrink-0 text-indigo-600" />
                                                            <span>Out: {formatAMPM(typeof slot?.morning_time_out_start === 'string' ? slot.morning_time_out_start : typeof slot?.time_out_start === 'string' ? slot.time_out_start : undefined)}</span>
                                                        </div>
                                                    </Link>
                                                </td>

                                                {/* 5. Afternoon Checkpoints */}
                                                <td className="px-4 sm:px-6 py-4 text-gray-700">
                                                    {hasAfternoon ? (
                                                        <Link href={`/admin/analytics/events/${item.event_id}`} className="block space-y-1">
                                                            <div className="flex items-center gap-1.5 text-xs font-bold text-amber-700" title="Afternoon Time-In">
                                                                <LogIn className="h-3 w-3 shrink-0 text-amber-600" />
                                                                <span>In: {formatAMPM(slot?.afternoon_time_in_start)}</span>
                                                            </div>
                                                            <div className="flex items-center gap-1.5 text-xs font-semibold text-purple-700" title="Afternoon Time-Out">
                                                                <LogOut className="h-3 w-3 shrink-0 text-purple-600" />
                                                                <span>Out: {formatAMPM(slot?.afternoon_time_out_start)}</span>
                                                            </div>
                                                        </Link>
                                                    ) : (
                                                        <span className="text-[11px] font-medium text-gray-400 italic">Disabled</span>
                                                    )}
                                                </td>

                                                {/* 6. Status */}
                                                <td className="px-4 sm:px-6 py-4">
                                                    <Link href={`/admin/analytics/events/${item.event_id}`} className="block">
                                                        <span
                                                            className={`inline-flex items-center gap-1.5 rounded-full px-3 py-0.5 text-xs font-bold border ${
                                                                item.is_active ? 'bg-emerald-50 text-emerald-700 border-emerald-200' : 'bg-gray-100 text-gray-600 border-gray-200'
                                                            }`}
                                                        >
                                                            <span className={`h-2 w-2 rounded-full ${item.is_active ? 'bg-emerald-500' : 'bg-gray-400'}`} aria-hidden="true" />
                                                            {item.is_active ? 'Active' : 'Inactive'}
                                                        </span>
                                                    </Link>
                                                </td>

                                                {/* 7. Actions */}
                                                <td className="px-4 sm:px-6 py-4 text-right">
                                                    <div className="flex items-center justify-end gap-1">
                                                        {activeTab === 'pending' && (
                                                            <>
                                                                <button
                                                                    type="button"
                                                                    onClick={() => handleQuickStatusChange(item, 'approved')}
                                                                    disabled={isQuickActing}
                                                                    className="rounded-lg p-2 min-h-[38px] text-emerald-700 hover:bg-emerald-50 focus-visible:ring-2 focus-visible:ring-[#F5A623] transition disabled:opacity-40"
                                                                    title="Approve Event"
                                                                    aria-label="Approve event"
                                                                >
                                                                    {isQuickActing ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-5 w-5" />}
                                                                </button>
                                                                <button
                                                                    type="button"
                                                                    onClick={() => handleQuickStatusChange(item, 'declined')}
                                                                    disabled={isQuickActing}
                                                                    className="rounded-lg p-2 min-h-[38px] text-rose-700 hover:bg-rose-50 focus-visible:ring-2 focus-visible:ring-[#F5A623] transition disabled:opacity-40"
                                                                    title="Decline Event"
                                                                    aria-label="Decline event"
                                                                >
                                                                    <XCircle className="h-5 w-5" />
                                                                </button>
                                                            </>
                                                        )}
                                                        <button
                                                            type="button"
                                                            onClick={() => openEditModal(item, true)}
                                                            className="rounded-lg p-2 min-h-[38px] text-gray-400 hover:bg-indigo-50 hover:text-[#1B1F5C] focus-visible:ring-2 focus-visible:ring-[#F5A623] transition"
                                                            title="Duplicate Event"
                                                            aria-label="Duplicate event"
                                                        >
                                                            <Copy className="h-4.5 w-4.5" />
                                                        </button>
                                                        <button
                                                            type="button"
                                                            onClick={() => openEditModal(item)}
                                                            className="rounded-lg p-2 min-h-[38px] text-gray-400 hover:bg-gray-100 hover:text-[#1B1F5C] focus-visible:ring-2 focus-visible:ring-[#F5A623] transition"
                                                            title="Edit Event"
                                                            aria-label="Edit event"
                                                        >
                                                            <Pencil className="h-4.5 w-4.5" />
                                                        </button>
                                                        <button
                                                            type="button"
                                                            onClick={() => promptDelete(item)}
                                                            className="rounded-lg p-2 min-h-[38px] text-gray-400 hover:bg-rose-50 hover:text-rose-600 focus-visible:ring-2 focus-visible:ring-[#F5A623] transition"
                                                            title="Delete Event"
                                                            aria-label="Delete event"
                                                        >
                                                            <Trash2 className="h-4.5 w-4.5" />
                                                        </button>
                                                    </div>
                                                </td>
                                            </tr>
                                        );
                                    })
                                ) : (
                                    <tr>
                                        <td colSpan={7} className="px-6 py-16 text-center text-gray-400 space-y-2">
                                            <div className="mx-auto flex h-10 w-10 items-center justify-center rounded-xl bg-indigo-50 text-[#1B1F5C]">
                                                <CalendarX className="h-5 w-5" aria-hidden="true" />
                                            </div>
                                            <p className="font-bold text-gray-900 text-sm">No {activeTab} events found.</p>
                                            <p className="text-xs text-gray-500">Try adjusting your search criteria or create a new event.</p>
                                        </td>
                                    </tr>
                                )}
                            </tbody>
                        </table>
                    </div>
                </main>

                {events.links.length > 3 && (
                    <nav className="flex flex-wrap items-center justify-center gap-1.5 pt-2" aria-label="Pagination">
                        {events.links.map((link, idx) => (
                            <Link
                                key={idx}
                                href={link.url ?? '#'}
                                preserveState
                                preserveScroll
                                className={`min-w-[2.25rem] min-h-[38px] flex items-center justify-center rounded-xl px-3.5 py-1.5 text-center text-xs font-bold transition-all focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                    link.active
                                        ? 'bg-[#1B1F5C] text-white shadow-xs'
                                        : link.url
                                        ? 'bg-white text-gray-700 border border-gray-200 hover:bg-gray-100'
                                        : 'bg-white text-gray-300 border border-gray-100 pointer-events-none'
                                }`}
                                dangerouslySetInnerHTML={{ __html: link.label }}
                            />
                        ))}
                    </nav>
                )}
            </div>

            {/* WIZARD FORM MODAL */}
            {isFormOpen && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-3 sm:p-4 backdrop-blur-xs">
                    <div className="flex w-full max-w-3xl max-h-[92vh] flex-col rounded-2xl bg-white shadow-xl transition-all border border-gray-200/80 overflow-hidden">
                        <header className="flex items-center justify-between border-b border-gray-100 p-4 sm:p-5">
                            <div className="flex items-center gap-3">
                                <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-indigo-50 text-[#1B1F5C] border border-indigo-100">
                                    <Calendar className="h-5 w-5" aria-hidden="true" />
                                </div>
                                <div>
                                    <h3 className="text-base sm:text-lg font-black text-[#1B1F5C]">
                                        {editingEvent ? 'Edit Event Details' : 'Create New Event'}
                                    </h3>
                                    <p className="text-xs font-medium text-gray-500">Step {currentStep} of 3: {
                                        currentStep === 1 ? 'Basic Info, Target Audience & Checkpoint Ranges' :
                                        currentStep === 2 ? 'Venue & Geofencing' : 'Review & Confirmation'
                                    }</p>
                                </div>
                            </div>
                            <button
                                onClick={() => setIsFormOpen(false)}
                                className="rounded-lg p-2 text-gray-400 hover:bg-gray-100 focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                aria-label="Close modal"
                            >
                                <X className="h-5 w-5" />
                            </button>
                        </header>

                        {(hasFormErrors || timeValidationError) && (
                            <div className="mx-4 sm:mx-6 mt-4 flex items-start gap-2.5 rounded-xl border border-rose-200 bg-rose-50 p-3.5 text-xs sm:text-sm text-rose-700" role="alert">
                                <AlertCircle className="h-5 w-5 shrink-0 mt-0.5" aria-hidden="true" />
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

                        <form id="event-form" onSubmit={handleFormSubmit} className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-5 text-xs sm:text-sm">
                            {/* STEP 1: BASIC INFO, TARGET AUDIENCE & CHECKPOINT RANGES */}
                            {currentStep === 1 && (
                                <div className="space-y-4 animate-fadeIn">
                                    <div>
                                        <label htmlFor="event-title" className="block font-bold uppercase tracking-wider text-gray-500 text-[10px]">
                                            Event Title *
                                        </label>
                                        <input
                                            id="event-title"
                                            type="text"
                                            required
                                            value={data.title}
                                            onChange={(e) => setData('title', e.target.value)}
                                            placeholder="e.g. University Sportsfest"
                                            className="mt-1 w-full min-h-[44px] rounded-xl border border-gray-300 bg-white px-3.5 py-2.5 text-gray-900 text-xs sm:text-sm font-medium focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] focus-visible:outline-none shadow-xs"
                                        />
                                    </div>

                                    <div>
                                        <label htmlFor="event-description" className="block font-bold uppercase tracking-wider text-gray-500 text-[10px]">
                                            Description
                                        </label>
                                        <textarea
                                            id="event-description"
                                            rows={2}
                                            value={data.description}
                                            onChange={(e) => setData('description', e.target.value)}
                                            placeholder="Optional details..."
                                            className="mt-1 w-full rounded-xl border border-gray-300 bg-white p-3.5 text-gray-900 text-xs sm:text-sm font-medium focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] focus-visible:outline-none shadow-xs"
                                        />
                                    </div>

                                    {/* TARGET AUDIENCE SCOPING */}
                                    <div className="space-y-2">
                                        <label className="block font-bold uppercase tracking-wider text-gray-500 text-[10px]">
                                            Participant Target Audience Scope
                                        </label>

                                        <div className="rounded-2xl border border-indigo-100 bg-indigo-50/30 p-3.5 space-y-3">
                                            <div className="grid grid-cols-2 gap-2">
                                                <button
                                                    type="button"
                                                    onClick={() => {
                                                        setData('target_scope', 'all');
                                                        setData('target_sections', []);
                                                    }}
                                                    className={`min-h-[44px] py-2 px-3 rounded-xl font-bold text-xs transition flex items-center justify-center gap-1.5 focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                                        data.target_scope === 'all'
                                                            ? 'bg-[#1B1F5C] text-white shadow-xs'
                                                            : 'bg-white text-gray-700 border border-gray-200 hover:bg-gray-50'
                                                    }`}
                                                >
                                                    All Students (University-wide)
                                                </button>
                                                <button
                                                    type="button"
                                                    onClick={() => setData('target_scope', 'section')}
                                                    className={`min-h-[44px] py-2 px-3 rounded-xl font-bold text-xs transition flex items-center justify-center gap-1.5 focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                                        data.target_scope === 'section'
                                                            ? 'bg-[#1B1F5C] text-white shadow-xs'
                                                            : 'bg-white text-gray-700 border border-gray-200 hover:bg-gray-50'
                                                    }`}
                                                >
                                                    Specific Course & Sections
                                                </button>
                                            </div>

                                            {data.target_scope === 'section' && (
                                                <div className="pt-2 space-y-2 animate-fadeIn">
                                                    <div className="flex items-center justify-between">
                                                        <span className="text-[10px] font-extrabold text-gray-500 uppercase tracking-wider">
                                                            Select Target Courses & Sections:
                                                        </span>
                                                        {availableSections.length > 0 && (
                                                            <button
                                                                type="button"
                                                                onClick={() => {
                                                                    const allSelected = data.target_sections.length === availableSections.length;
                                                                    setData('target_sections', allSelected ? [] : [...availableSections]);
                                                                }}
                                                                className="text-[11px] font-bold text-[#1B1F5C] hover:underline flex items-center gap-1"
                                                            >
                                                                {data.target_sections.length === availableSections.length ? (
                                                                    <>
                                                                        <Square className="h-3 w-3" /> Clear All
                                                                    </>
                                                                ) : (
                                                                    <>
                                                                        <CheckSquare className="h-3 w-3" /> Select All
                                                                    </>
                                                                )}
                                                            </button>
                                                        )}
                                                    </div>

                                                    {availableSections.length === 0 ? (
                                                        <p className="text-xs text-amber-700 italic bg-amber-50 p-3 rounded-xl border border-amber-200">
                                                            No student records with course/section found in Student Management yet. You can still publish as 'All Students'.
                                                        </p>
                                                    ) : (
                                                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 max-h-48 overflow-y-auto pr-1">
                                                            {availableSections.map((sectionStr) => {
                                                                const isSelected = data.target_sections.includes(sectionStr);
                                                                return (
                                                                    <button
                                                                        key={sectionStr}
                                                                        type="button"
                                                                        onClick={() => {
                                                                            const updated = isSelected
                                                                                ? data.target_sections.filter(s => s !== sectionStr)
                                                                                : [...data.target_sections, sectionStr];
                                                                            setData('target_sections', updated);
                                                                        }}
                                                                        className={`w-full min-h-[40px] px-3.5 py-2 rounded-xl text-xs font-bold transition flex items-center justify-between text-left focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                                                            isSelected
                                                                                ? 'bg-[#1B1F5C] text-white shadow-xs'
                                                                                : 'bg-white text-gray-700 border border-gray-200 hover:bg-gray-50'
                                                                        }`}
                                                                    >
                                                                        <span className="truncate pr-2">{sectionStr}</span>
                                                                        {isSelected && <Check className="h-4 w-4 shrink-0" />}
                                                                    </button>
                                                                );
                                                            })}
                                                        </div>
                                                    )}
                                                </div>
                                            )}
                                        </div>
                                    </div>

                                    <div className="rounded-2xl border border-gray-200 bg-gray-50/50 p-4 space-y-3">
                                        <FormSwitch
                                            checked={isMultiDay}
                                            onCheckedChange={(checked: boolean) => {
                                                setIsMultiDay(checked);
                                                if (!checked) setData('event_end_date', '');
                                            }}
                                            label="Enable Multi-Day Event (Span Range)"
                                        />

                                        <div className={`grid ${isMultiDay ? 'grid-cols-1 sm:grid-cols-2' : 'grid-cols-1'} gap-3`}>
                                            <div>
                                                <label htmlFor="event-date" className="block font-bold uppercase tracking-wider text-gray-500 text-[10px]">
                                                    {isMultiDay ? 'Start Date *' : 'Event Date *'}
                                                </label>
                                                <input
                                                    id="event-date"
                                                    type="date"
                                                    required
                                                    value={data.event_date}
                                                    onChange={(e) => setData('event_date', e.target.value)}
                                                    className="mt-1 w-full min-h-[44px] rounded-xl border border-gray-300 bg-white px-3.5 py-2.5 text-gray-900 text-xs sm:text-sm font-medium focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] focus-visible:outline-none shadow-xs"
                                                />
                                            </div>

                                            {isMultiDay && (
                                                <div>
                                                    <label htmlFor="event-end-date" className="block font-bold uppercase tracking-wider text-gray-500 text-[10px]">
                                                        End Date *
                                                    </label>
                                                    <input
                                                        id="event-end-date"
                                                        type="date"
                                                        required={isMultiDay}
                                                        min={data.event_date}
                                                        value={data.event_end_date || ''}
                                                        onChange={(e) => setData('event_end_date', e.target.value)}
                                                        className="mt-1 w-full min-h-[44px] rounded-xl border border-gray-300 bg-white px-3.5 py-2.5 text-gray-900 text-xs sm:text-sm font-medium focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] focus-visible:outline-none shadow-xs"
                                                    />
                                                </div>
                                            )}
                                        </div>
                                    </div>

                                    {isMultiDay && (
                                        <div className="rounded-2xl border border-indigo-100 bg-indigo-50/40 p-4 space-y-3">
                                            <label className="block font-bold text-[#1B1F5C] uppercase tracking-wider text-[10px]">
                                                Multi-Day Schedule Mode
                                            </label>
                                            <div className="grid grid-cols-2 gap-2">
                                                <button
                                                    type="button"
                                                    onClick={() => setScheduleMode('uniform')}
                                                    className={`min-h-[44px] py-2 px-3 rounded-xl font-bold text-xs transition flex items-center justify-center gap-1.5 focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                                        scheduleMode === 'uniform'
                                                            ? 'bg-[#1B1F5C] text-white shadow-xs'
                                                            : 'bg-white text-gray-700 border border-gray-200 hover:bg-gray-50'
                                                    }`}
                                                >
                                                    Uniform Schedule (Same Hours Daily)
                                                </button>
                                                <button
                                                    type="button"
                                                    onClick={() => setScheduleMode('custom')}
                                                    className={`min-h-[44px] py-2 px-3 rounded-xl font-bold text-xs transition flex items-center justify-center gap-1.5 focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                                        scheduleMode === 'custom'
                                                            ? 'bg-[#1B1F5C] text-white shadow-xs'
                                                            : 'bg-white text-gray-700 border border-gray-200 hover:bg-gray-50'
                                                    }`}
                                                >
                                                    Custom Daily Schedule (Different Hours)
                                                </button>
                                            </div>
                                        </div>
                                    )}

                                    {/* UNIFORM CHECKPOINT RANGES CONFIGURATION */}
                                    {isMultiDay && scheduleMode === 'uniform' && (
                                        <div className="rounded-2xl border border-emerald-100 bg-emerald-50/40 p-4 space-y-4">
                                            <div className="flex items-center justify-between">
                                                <div className="flex items-center gap-2 font-bold text-emerald-800 text-xs">
                                                    <Calendar className="h-4 w-4" />
                                                    <span>Uniform Checkpoint Ranges (Applied to All Days)</span>
                                                </div>
                                                <FormSwitch
                                                    checked={Boolean(uniformSchedule.has_afternoon)}
                                                    onCheckedChange={(checked: boolean) => handleUniformChange('has_afternoon', checked)}
                                                    label="Enable Afternoon Session"
                                                />
                                            </div>

                                            {/* Morning Checkpoints */}
                                            <div className="p-3 bg-white rounded-xl border border-emerald-200 space-y-3">
                                                <div className="flex items-center gap-1.5 text-xs font-extrabold text-blue-800">
                                                    <Sun className="h-4 w-4 text-blue-600" />
                                                    <span>Morning Session (Time-In & Time-Out Ranges)</span>
                                                </div>
                                                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                                                    <div>
                                                        <label className="block font-bold text-gray-700 text-[10px]">Morning Time-In Window (Start to Cut-Off) *</label>
                                                        <div className="flex items-center gap-2 mt-1">
                                                            <input
                                                                type="time"
                                                                value={uniformSchedule.morning_time_in_start ?? ''}
                                                                onChange={(e) => handleUniformChange('morning_time_in_start', e.target.value)}
                                                                className="w-full min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-gray-900 font-medium text-xs focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                            />
                                                            <span className="text-gray-400 text-xs font-bold">to</span>
                                                            <input
                                                                type="time"
                                                                value={uniformSchedule.morning_time_in_end ?? ''}
                                                                onChange={(e) => handleUniformChange('morning_time_in_end', e.target.value)}
                                                                className="w-full min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-gray-900 font-medium text-xs focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                            />
                                                        </div>
                                                    </div>
                                                    <div>
                                                        <label className="block font-bold text-gray-700 text-[10px]">Morning Time-Out Window (Start to Cut-Off)</label>
                                                        <div className="flex items-center gap-2 mt-1">
                                                            <input
                                                                type="time"
                                                                value={uniformSchedule.morning_time_out_start ?? ''}
                                                                onChange={(e) => handleUniformChange('morning_time_out_start', e.target.value)}
                                                                className="w-full min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-gray-900 font-medium text-xs focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                            />
                                                            <span className="text-gray-400 text-xs font-bold">to</span>
                                                            <input
                                                                type="time"
                                                                value={uniformSchedule.morning_time_out_end ?? ''}
                                                                onChange={(e) => handleUniformChange('morning_time_out_end', e.target.value)}
                                                                className="w-full min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-gray-900 font-medium text-xs focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                            />
                                                        </div>
                                                    </div>
                                                </div>
                                            </div>

                                            {/* Afternoon Checkpoints (Optional) */}
                                            {uniformSchedule.has_afternoon && (
                                                <div className="p-3 bg-white rounded-xl border border-emerald-200 space-y-3 animate-fadeIn">
                                                    <div className="flex items-center gap-1.5 text-xs font-extrabold text-amber-800">
                                                        <Sunset className="h-4 w-4 text-amber-600" />
                                                        <span>Afternoon Session (Time-In & Time-Out Ranges)</span>
                                                    </div>
                                                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                                                        <div>
                                                            <label className="block font-bold text-gray-700 text-[10px]">Afternoon Time-In Window (Start to Cut-Off)</label>
                                                            <div className="flex items-center gap-2 mt-1">
                                                                <input
                                                                    type="time"
                                                                    value={uniformSchedule.afternoon_time_in_start ?? ''}
                                                                    onChange={(e) => handleUniformChange('afternoon_time_in_start', e.target.value)}
                                                                    className="w-full min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-gray-900 font-medium text-xs focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                                />
                                                                <span className="text-gray-400 text-xs font-bold">to</span>
                                                                <input
                                                                    type="time"
                                                                    value={uniformSchedule.afternoon_time_in_end ?? ''}
                                                                    onChange={(e) => handleUniformChange('afternoon_time_in_end', e.target.value)}
                                                                    className="w-full min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-gray-900 font-medium text-xs focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                                />
                                                            </div>
                                                        </div>
                                                        <div>
                                                            <label className="block font-bold text-gray-700 text-[10px]">Afternoon Time-Out Window (Start to Cut-Off)</label>
                                                            <div className="flex items-center gap-2 mt-1">
                                                                <input
                                                                    type="time"
                                                                    value={uniformSchedule.afternoon_time_out_start ?? ''}
                                                                    onChange={(e) => handleUniformChange('afternoon_time_out_start', e.target.value)}
                                                                    className="w-full min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-gray-900 font-medium text-xs focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                                />
                                                                <span className="text-gray-400 text-xs font-bold">to</span>
                                                                <input
                                                                    type="time"
                                                                    value={uniformSchedule.afternoon_time_out_end ?? ''}
                                                                    onChange={(e) => handleUniformChange('afternoon_time_out_end', e.target.value)}
                                                                    className="w-full min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-gray-900 font-medium text-xs focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                                />
                                                            </div>
                                                        </div>
                                                    </div>
                                                </div>
                                            )}
                                        </div>
                                    )}

                                    {/* CUSTOM CHECKPOINT RANGES PER SLOT/DAY */}
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
                                                                    : 'Event Schedule & Checkpoint Ranges'}
                                                            </span>
                                                        </div>

                                                        <button
                                                            type="button"
                                                            onClick={() => {
                                                                const updated = [...data.schedules];
                                                                updated[dayIndex].slots.push({ ...DEFAULT_SLOT });
                                                                setData('schedules', updated);
                                                                validateTimeSlots(updated as any, setTimeValidationError);
                                                            }}
                                                            className="inline-flex items-center gap-1 rounded-xl bg-emerald-600 px-3 py-1.5 text-xs font-bold text-white hover:bg-emerald-700 focus-visible:ring-2 focus-visible:ring-[#F5A623] transition"
                                                        >
                                                            <Plus className="h-4 w-4" />
                                                            <span>Add Time Slot</span>
                                                        </button>
                                                    </div>

                                                    {schedule.slots.map((slot, slotIndex) => {
                                                        const slotHasAfternoon = Boolean(slot.has_afternoon);
                                                        return (
                                                            <div key={slotIndex} className="relative rounded-xl border border-emerald-200 bg-white p-4 space-y-4 shadow-2xs">
                                                                {schedule.slots.length > 1 && (
                                                                    <button
                                                                        type="button"
                                                                        onClick={() => {
                                                                            const updated = [...data.schedules];
                                                                            updated[dayIndex].slots.splice(slotIndex, 1);
                                                                            setData('schedules', updated);
                                                                            validateTimeSlots(updated as any, setTimeValidationError);
                                                                        }}
                                                                        className="absolute right-2 top-2 rounded-lg p-1 text-gray-400 hover:bg-rose-50 hover:text-rose-600 focus-visible:ring-2 focus-visible:ring-[#F5A623] transition"
                                                                        title="Remove Slot"
                                                                        aria-label="Remove time slot"
                                                                    >
                                                                        <X className="h-4 w-4" />
                                                                    </button>
                                                                )}

                                                                <div className="flex items-center justify-between border-b pb-2">
                                                                    <span className="text-[11px] font-extrabold uppercase text-emerald-800 tracking-wider">
                                                                        Slot {slotIndex + 1} Configuration
                                                                    </span>
                                                                    <FormSwitch
                                                                        checked={slotHasAfternoon}
                                                                        onCheckedChange={(checked: boolean) => {
                                                                            const updated = [...data.schedules];
                                                                            updated[dayIndex].slots[slotIndex] = {
                                                                                ...updated[dayIndex].slots[slotIndex],
                                                                                has_afternoon: checked,
                                                                                afternoon_time_in_start: checked ? (updated[dayIndex].slots[slotIndex].afternoon_time_in_start || '13:00') : '',
                                                                                afternoon_time_in_end: checked ? (updated[dayIndex].slots[slotIndex].afternoon_time_in_end || '13:30') : '',
                                                                                afternoon_time_out_start: checked ? (updated[dayIndex].slots[slotIndex].afternoon_time_out_start || '16:30') : '',
                                                                                afternoon_time_out_end: checked ? (updated[dayIndex].slots[slotIndex].afternoon_time_out_end || '17:00') : '',
                                                                            };
                                                                            setData('schedules', updated);
                                                                            validateTimeSlots(updated as any, setTimeValidationError);
                                                                        }}
                                                                        label="Enable Afternoon Session"
                                                                    />
                                                                </div>

                                                                {/* Morning Session */}
                                                                <div className="space-y-2 bg-blue-50/40 p-3 rounded-xl border border-blue-100">
                                                                    <div className="flex items-center gap-1 text-xs font-bold text-blue-800">
                                                                        <Sun className="h-3.5 w-3.5 text-blue-600" />
                                                                        <span>Morning Session (Time-In & Time-Out Ranges)</span>
                                                                    </div>
                                                                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                                                                        <div>
                                                                            <label className="block font-bold text-gray-700 text-[10px]">Morning Time-In Window (Start to Cut-Off) *</label>
                                                                            <div className="flex items-center gap-2 mt-1">
                                                                                <input
                                                                                    type="time"
                                                                                    required
                                                                                    value={slot.morning_time_in_start ?? ''}
                                                                                    onChange={(e) => {
                                                                                        const updated = [...data.schedules];
                                                                                        updated[dayIndex].slots[slotIndex].morning_time_in_start = e.target.value;
                                                                                        setData('schedules', updated);
                                                                                        validateTimeSlots(updated as any, setTimeValidationError);
                                                                                    }}
                                                                                    className="w-full min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-gray-900 font-medium text-xs focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                                                />
                                                                                <span className="text-gray-400 text-xs font-bold">to</span>
                                                                                <input
                                                                                    type="time"
                                                                                    value={slot.morning_time_in_end ?? ''}
                                                                                    onChange={(e) => {
                                                                                        const updated = [...data.schedules];
                                                                                        updated[dayIndex].slots[slotIndex].morning_time_in_end = e.target.value;
                                                                                        setData('schedules', updated);
                                                                                        validateTimeSlots(updated as any, setTimeValidationError);
                                                                                    }}
                                                                                    className="w-full min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-gray-900 font-medium text-xs focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                                                />
                                                                            </div>
                                                                        </div>
                                                                        <div>
                                                                            <label className="block font-bold text-gray-700 text-[10px]">Morning Time-Out Window (Start to Cut-Off)</label>
                                                                            <div className="flex items-center gap-2 mt-1">
                                                                                <input
                                                                                    type="time"
                                                                                    value={slot.morning_time_out_start ?? ''}
                                                                                    onChange={(e) => {
                                                                                        const updated = [...data.schedules];
                                                                                        updated[dayIndex].slots[slotIndex].morning_time_out_start = e.target.value;
                                                                                        setData('schedules', updated);
                                                                                        validateTimeSlots(updated as any, setTimeValidationError);
                                                                                    }}
                                                                                    className="w-full min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-gray-900 font-medium text-xs focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                                                />
                                                                                <span className="text-gray-400 text-xs font-bold">to</span>
                                                                                <input
                                                                                    type="time"
                                                                                    value={slot.morning_time_out_end ?? ''}
                                                                                    onChange={(e) => {
                                                                                        const updated = [...data.schedules];
                                                                                        updated[dayIndex].slots[slotIndex].morning_time_out_end = e.target.value;
                                                                                        setData('schedules', updated);
                                                                                        validateTimeSlots(updated as any, setTimeValidationError);
                                                                                    }}
                                                                                    className="w-full min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-gray-900 font-medium text-xs focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                                                />
                                                                            </div>
                                                                        </div>
                                                                    </div>
                                                                </div>

                                                                {/* Afternoon Session (Optional) */}
                                                                {slotHasAfternoon && (
                                                                    <div className="space-y-2 bg-amber-50/40 p-3 rounded-xl border border-amber-100 animate-fadeIn">
                                                                        <div className="flex items-center gap-1 text-xs font-bold text-amber-800">
                                                                            <Sunset className="h-3.5 w-3.5 text-amber-600" />
                                                                            <span>Afternoon Session (Time-In & Time-Out Ranges)</span>
                                                                        </div>
                                                                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                                                                            <div>
                                                                                <label className="block font-bold text-gray-700 text-[10px]">Afternoon Time-In Window (Start to Cut-Off)</label>
                                                                                <div className="flex items-center gap-2 mt-1">
                                                                                    <input
                                                                                        type="time"
                                                                                        value={slot.afternoon_time_in_start ?? ''}
                                                                                        onChange={(e) => {
                                                                                            const updated = [...data.schedules];
                                                                                            updated[dayIndex].slots[slotIndex].afternoon_time_in_start = e.target.value;
                                                                                            setData('schedules', updated);
                                                                                            validateTimeSlots(updated as any, setTimeValidationError);
                                                                                        }}
                                                                                        className="w-full min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-gray-900 font-medium text-xs focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                                                    />
                                                                                    <span className="text-gray-400 text-xs font-bold">to</span>
                                                                                    <input
                                                                                        type="time"
                                                                                        value={slot.afternoon_time_in_end ?? ''}
                                                                                        onChange={(e) => {
                                                                                            const updated = [...data.schedules];
                                                                                            updated[dayIndex].slots[slotIndex].afternoon_time_in_end = e.target.value;
                                                                                            setData('schedules', updated);
                                                                                            validateTimeSlots(updated as any, setTimeValidationError);
                                                                                        }}
                                                                                        className="w-full min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-gray-900 font-medium text-xs focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                                                    />
                                                                                </div>
                                                                            </div>
                                                                            <div>
                                                                                <label className="block font-bold text-gray-700 text-[10px]">Afternoon Time-Out Window (Start to Cut-Off)</label>
                                                                                <div className="flex items-center gap-2 mt-1">
                                                                                    <input
                                                                                        type="time"
                                                                                        value={slot.afternoon_time_out_start ?? ''}
                                                                                        onChange={(e) => {
                                                                                            const updated = [...data.schedules];
                                                                                            updated[dayIndex].slots[slotIndex].afternoon_time_out_start = e.target.value;
                                                                                            setData('schedules', updated);
                                                                                            validateTimeSlots(updated as any, setTimeValidationError);
                                                                                        }}
                                                                                        className="w-full min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-gray-900 font-medium text-xs focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                                                    />
                                                                                    <span className="text-gray-400 text-xs font-bold">to</span>
                                                                                    <input
                                                                                        type="time"
                                                                                        value={slot.afternoon_time_out_end ?? ''}
                                                                                        onChange={(e) => {
                                                                                            const updated = [...data.schedules];
                                                                                            updated[dayIndex].slots[slotIndex].afternoon_time_out_end = e.target.value;
                                                                                            setData('schedules', updated);
                                                                                            validateTimeSlots(updated as any, setTimeValidationError);
                                                                                        }}
                                                                                        className="w-full min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-gray-900 font-medium text-xs focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                                                    />
                                                                                </div>
                                                                            </div>
                                                                        </div>
                                                                    </div>
                                                                )}
                                                            </div>
                                                        );
                                                    })}
                                                </div>
                                            );
                                        })}
                                </div>
                            )}

                            {/* STEP 2: VENUE & GEOFENCING */}
                            {currentStep === 2 && (
                                <div className="space-y-4 animate-fadeIn">
                                    <div>
                                        <div className="flex items-center justify-between flex-wrap gap-2">
                                            <label htmlFor="event-location" className="block font-bold uppercase tracking-wider text-gray-500 text-[10px]">
                                                Venue Name
                                            </label>
                                            {venues.length > 0 && (
                                                <div className="flex items-center gap-1.5 flex-wrap justify-end">
                                                    <Building2 className="h-3.5 w-3.5 text-gray-400" />
                                                    <span className="text-[10px] font-bold text-gray-400 uppercase">Saved Venues:</span>
                                                    {venues.map((venue, idx) => (
                                                        <button
                                                            key={idx}
                                                            type="button"
                                                            onClick={() => handleApplyVenuePreset(venue)}
                                                            className="text-[11px] font-bold text-[#1B1F5C] bg-indigo-50 hover:bg-indigo-100 px-2.5 py-1 rounded-lg focus-visible:ring-2 focus-visible:ring-[#F5A623] transition"
                                                        >
                                                            {venue.location}
                                                        </button>
                                                    ))}
                                                </div>
                                            )}
                                        </div>

                                        <div className="mt-1 flex items-center gap-2">
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
                                                className="w-full min-h-[44px] rounded-xl border border-gray-300 bg-white px-3.5 py-2.5 text-gray-900 text-xs sm:text-sm font-medium focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] focus-visible:outline-none shadow-xs"
                                            />
                                            <button
                                                type="button"
                                                onClick={() => geocodeVenueName()}
                                                disabled={isSearchingLocation}
                                                className="min-h-[44px] min-w-[44px] rounded-xl bg-blue-50 border border-blue-200 p-2.5 text-blue-700 hover:bg-blue-100 font-bold focus-visible:ring-2 focus-visible:ring-[#F5A623] transition shrink-0 flex items-center justify-center"
                                                title="Locate Venue on Map"
                                                aria-label="Locate venue on map"
                                            >
                                                {isSearchingLocation ? (
                                                    <Loader2 className="h-5 w-5 animate-spin text-blue-600" />
                                                ) : (
                                                    <Search className="h-5 w-5" />
                                                )}
                                            </button>
                                        </div>
                                        {geocodeConfirmation && (
                                            <p className="mt-1.5 flex items-center gap-1.5 text-xs text-emerald-700 font-semibold">
                                                <CheckCircle2 className="h-4 w-4 shrink-0" />
                                                <span className="truncate">Matched: {geocodeConfirmation}</span>
                                            </p>
                                        )}
                                    </div>

                                    <div className="rounded-2xl border border-indigo-100 bg-indigo-50/30 p-4 space-y-3">
                                        <div className="flex items-center justify-between">
                                            <div className="flex items-center gap-2 font-bold text-[#1B1F5C] text-xs">
                                                <Navigation className="h-4 w-4 text-[#F5A623]" />
                                                <span>GPS Geofence Location Boundary</span>
                                            </div>
                                            <FormSwitch
                                                checked={data.is_geofenced}
                                                onCheckedChange={(checked: boolean) => setData('is_geofenced', checked)}
                                                label="Enforce Geofence"
                                                activeClass="peer-checked:bg-[#1B1F5C]"
                                            />
                                        </div>

                                        {data.is_geofenced && (
                                            <div className="space-y-3 pt-2 border-t border-indigo-100">
                                                <div className="grid grid-cols-2 gap-2 bg-indigo-100/50 p-1 rounded-xl">
                                                    <button
                                                        type="button"
                                                        onClick={() => setData('geofence_type', 'radius')}
                                                        className={`min-h-[38px] py-1.5 px-3 rounded-lg font-bold text-xs transition flex items-center justify-center gap-1.5 focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                                            data.geofence_type === 'radius'
                                                                ? 'bg-white text-[#1B1F5C] shadow-xs'
                                                                : 'text-gray-600 hover:text-gray-900'
                                                        }`}
                                                    >
                                                        <CircleDot className="h-4 w-4 text-[#F5A623]" />
                                                        <span>Circular Radius</span>
                                                    </button>
                                                    <button
                                                        type="button"
                                                        onClick={() => setData('geofence_type', 'polygon')}
                                                        className={`min-h-[38px] py-1.5 px-3 rounded-lg font-bold text-xs transition flex items-center justify-center gap-1.5 focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                                            data.geofence_type === 'polygon'
                                                                ? 'bg-white text-[#1B1F5C] shadow-xs'
                                                                : 'text-gray-600 hover:text-gray-900'
                                                        }`}
                                                    >
                                                        <Hexagon className="h-4 w-4 text-[#F5A623]" />
                                                        <span>Hexagon Area</span>
                                                    </button>
                                                </div>

                                                {data.geofence_type === 'radius' && (
                                                    <div>
                                                        <div className="flex items-center justify-between text-xs font-bold text-gray-700 mb-1.5">
                                                            <span>Check-In Radius:</span>
                                                            <span className="text-[#1B1F5C] font-extrabold">{data.radius_meters} meters</span>
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

                            {/* STEP 3: REVIEW & CONFIRMATION */}
                            {currentStep === 3 && (
                                <div className="space-y-4 animate-fadeIn">
                                    <div className="rounded-2xl border border-gray-200 bg-gray-50 p-4 space-y-3">
                                        <div className="flex items-center gap-2 font-bold text-[#1B1F5C] text-sm">
                                            <FileText className="h-4 w-4 text-[#F5A623]" />
                                            <span>Event Configuration Summary ({data.schedules.length} {data.schedules.length === 1 ? 'Day' : 'Days'})</span>
                                        </div>

                                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-xs sm:text-sm pt-2 border-t border-gray-200">
                                            <div>
                                                <span className="text-gray-400 block font-bold uppercase tracking-wider text-[10px]">Title</span>
                                                <p className="font-extrabold text-gray-900 mt-0.5">{data.title || 'Untitled Event'}</p>
                                            </div>
                                            <div>
                                                <span className="text-gray-400 block font-bold uppercase tracking-wider text-[10px]">Target Audience</span>
                                                <p className="font-bold text-[#1B1F5C] mt-0.5">
                                                    {data.target_scope === 'all' ? 'All Students (University-wide)' : `${data.target_sections.length} Section(s) Selected`}
                                                </p>
                                            </div>
                                            <div>
                                                <span className="text-gray-400 block font-bold uppercase tracking-wider text-[10px]">Date Span</span>
                                                <p className="font-bold text-gray-900 mt-0.5">
                                                    {data.event_date ? formatDate(data.event_date) : 'Not set'}
                                                    {data.event_end_date && data.event_end_date !== data.event_date
                                                        ? ` to ${formatDate(data.event_end_date)}`
                                                        : ''}
                                                </p>
                                            </div>
                                            <div>
                                                <span className="text-gray-400 block font-bold uppercase tracking-wider text-[10px]">Venue</span>
                                                <p className="font-bold text-gray-900 mt-0.5">{data.location || 'Unspecified Venue'}</p>
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

                        <footer className="flex items-center justify-between border-t border-gray-100 p-4 sm:p-5 bg-white">
                            <div>
                                {currentStep > 1 && (
                                    <button
                                        type="button"
                                        onClick={() => setCurrentStep(currentStep - 1)}
                                        className="inline-flex items-center gap-1.5 min-h-[44px] rounded-xl border border-gray-300 px-4 py-2.5 font-bold text-gray-700 hover:bg-gray-50 focus-visible:ring-2 focus-visible:ring-[#F5A623] text-xs sm:text-sm"
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
                                    className="min-h-[44px] rounded-xl border border-gray-300 px-4 py-2.5 font-bold text-gray-700 hover:bg-gray-50 focus-visible:ring-2 focus-visible:ring-[#F5A623] text-xs sm:text-sm"
                                >
                                    Cancel
                                </button>

                                {currentStep < 3 ? (
                                    <button
                                        type="button"
                                        onClick={() => setCurrentStep(currentStep + 1)}
                                        className="inline-flex items-center gap-1.5 min-h-[44px] rounded-xl bg-[#1B1F5C] px-5 py-2.5 font-bold text-white hover:bg-[#131644] focus-visible:ring-2 focus-visible:ring-[#F5A623] text-xs sm:text-sm shadow-md"
                                    >
                                        <span>Next Step</span>
                                        <ArrowRight className="h-4 w-4 text-[#F5A623]" />
                                    </button>
                                ) : (
                                    <button
                                        type="submit"
                                        form="event-form"
                                        disabled={processing || Boolean(timeValidationError)}
                                        className="min-h-[44px] rounded-xl bg-[#1B1F5C] px-5 py-2.5 font-bold text-white hover:bg-[#131644] focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-50 text-xs sm:text-sm shadow-md"
                                    >
                                        {processing ? 'Saving...' : editingEvent ? 'Save Changes' : 'Create Event'}
                                    </button>
                                )}
                            </div>
                        </footer>
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