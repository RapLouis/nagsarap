import React, { useState, useMemo } from 'react';
import { Head, router } from '@inertiajs/react';
import AppLayout from '@/layouts/app-layout'; // Adjust import to your student layout wrapper
import {
    Bell,
    CheckCheck,
    CheckCircle2,
    AlertCircle,
    Clock,
    Calendar,
    Shield,
    Info,
    Check,
} from 'lucide-react';

interface NotificationItem {
    notification_id: number;
    type: string;
    title: string;
    message: string;
    is_read: boolean;
    read_at: string | null;
    created_at: string;
}

interface PageProps {
    notifications: NotificationItem[];
    unreadCount: number;
}

export default function Notifications({ notifications = [], unreadCount = 0 }: PageProps) {
    const [activeTab, setActiveTab] = useState<'all' | 'unread' | 'attendance' | 'events' | 'system'>('all');

    const handleMarkAsRead = (id: number) => {
        router.patch(`/notifications/${id}/read`, {}, { preserveScroll: true });
    };

    const handleMarkAllAsRead = () => {
        router.patch('/notifications/read-all', {}, { preserveScroll: true });
    };

    const filteredNotifications = useMemo(() => {
        return notifications.filter((item) => {
            if (activeTab === 'unread') return !item.is_read;
            if (activeTab === 'attendance') return item.type === 'attendance' || item.type === 'success' || item.type === 'error';
            if (activeTab === 'events') return item.type === 'event' || item.type === 'announcement';
            if (activeTab === 'system') return item.type === 'security' || item.type === 'biometric' || item.type === 'warning' || item.type === 'clearance';
            return true;
        });
    }, [notifications, activeTab]);

    const getIconForType = (type: string) => {
        switch (type) {
            case 'success':
            case 'attendance':
                return <CheckCircle2 className="h-5 w-5 text-emerald-600" />;
            case 'error':
            case 'warning':
                return <AlertCircle className="h-5 w-5 text-rose-600" />;
            case 'reminder':
                return <Clock className="h-5 w-5 text-amber-600" />;
            case 'event':
            case 'announcement':
                return <Calendar className="h-5 w-5 text-indigo-600" />;
            case 'security':
            case 'biometric':
                return <Shield className="h-5 w-5 text-purple-600" />;
            default:
                return <Info className="h-5 w-5 text-[#1B1F5C]" />;
        }
    };

    return (
        <>
            <Head title="Notification Center | 4ttnd Attendance System" />

            <div className="p-4 sm:p-8 font-sans text-gray-900 antialiased bg-[#F5F6FA] min-h-screen space-y-6">
                {/* HEADER & ACTIONS */}
                <header className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-white p-5 rounded-2xl border border-gray-200/80 shadow-xs">
                    <div className="space-y-1">
                        <h1 className="text-xl sm:text-2xl font-black text-[#1B1F5C] tracking-tight flex items-center gap-2">
                            <span>Notification Center</span>
                            {unreadCount > 0 && (
                                <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-extrabold bg-amber-100 text-amber-800 border border-amber-200">
                                    {unreadCount} Unread
                                </span>
                            )}
                        </h1>
                        <p className="text-xs text-gray-500 font-medium">
                            Stay updated on attendance confirmations, time-window reminders, and important academic announcements.
                        </p>
                    </div>

                    {unreadCount > 0 && (
                        <button
                            onClick={handleMarkAllAsRead}
                            className="inline-flex items-center justify-center gap-2 px-4 py-2.5 bg-[#1B1F5C] hover:bg-[#131644] active:scale-98 text-white text-xs font-bold rounded-xl shadow-md transition-all cursor-pointer"
                        >
                            <CheckCheck className="w-4 h-4 text-[#F5A623]" />
                            <span>Mark all as read</span>
                        </button>
                    )}
                </header>

                {/* FILTER TABS */}
                <div className="flex flex-wrap items-center gap-2 border-b border-gray-200 pb-3">
                    {[
                        { id: 'all', label: `All (${notifications.length})` },
                        { id: 'unread', label: `Unread (${unreadCount})` },
                        { id: 'attendance', label: 'Attendance' },
                        { id: 'events', label: 'Events' },
                        { id: 'system', label: 'System & Security' },
                    ].map((tab) => (
                        <button
                            key={tab.id}
                            onClick={() => setActiveTab(tab.id as any)}
                            className={`px-4 py-2 rounded-xl text-xs font-bold transition-all ${
                                activeTab === tab.id
                                    ? 'bg-[#1B1F5C] text-white shadow-sm'
                                    : 'bg-white text-gray-600 border border-gray-200 hover:bg-gray-50'
                            }`}
                        >
                            {tab.label}
                        </button>
                    ))}
                </div>

                {/* NOTIFICATIONS LIST */}
                <div className="space-y-3">
                    {filteredNotifications.length > 0 ? (
                        filteredNotifications.map((notif) => (
                            <div
                                key={notif.notification_id}
                                onClick={() => !notif.is_read && handleMarkAsRead(notif.notification_id)}
                                className={`flex items-start gap-4 p-4 sm:p-5 rounded-2xl border transition-all cursor-pointer ${
                                    notif.is_read
                                        ? 'bg-white border-gray-200/80 opacity-85'
                                        : 'bg-amber-50/40 border-amber-200 shadow-sm ring-1 ring-amber-100'
                                }`}
                            >
                                <div className="shrink-0 mt-0.5 p-2.5 rounded-xl bg-white border border-gray-100 shadow-2xs">
                                    {getIconForType(notif.type)}
                                </div>

                                <div className="flex-1 min-w-0">
                                    <div className="flex items-center justify-between gap-2 mb-1">
                                        <h3 className={`text-xs sm:text-sm font-extrabold ${notif.is_read ? 'text-gray-800' : 'text-[#1B1F5C]'}`}>
                                            {notif.title}
                                        </h3>
                                        <span className="text-[11px] text-gray-400 font-semibold shrink-0">
                                            {notif.created_at}
                                        </span>
                                    </div>
                                    <p className="text-xs text-gray-600 leading-relaxed font-medium">
                                        {notif.message}
                                    </p>
                                </div>

                                {!notif.is_read && (
                                    <button
                                        onClick={(e) => {
                                            e.stopPropagation();
                                            handleMarkAsRead(notif.notification_id);
                                        }}
                                        title="Mark as read"
                                        className="shrink-0 p-2 text-gray-400 hover:text-[#1B1F5C] hover:bg-white rounded-xl transition"
                                    >
                                        <Check className="w-4 h-4 text-amber-600" />
                                    </button>
                                )}
                            </div>
                        ))
                    ) : (
                        <div className="py-16 text-center space-y-3 bg-white rounded-2xl border border-gray-200/80">
                            <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-gray-100 text-gray-400 mx-auto">
                                <Bell className="w-6 h-6" />
                            </div>
                            <p className="text-xs font-bold text-gray-700">You're all caught up!</p>
                            <p className="text-[11px] text-gray-400">No notifications match your current filter.</p>
                        </div>
                    )}
                </div>
            </div>
        </>
    );
}

Notifications.layout = (page: React.ReactNode) => (
    <AppLayout breadcrumbs={[{ title: 'Notifications', href: '/notifications' }]}>
        {page}
    </AppLayout>
);