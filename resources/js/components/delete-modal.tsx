import React from 'react';
import { Trash2 } from 'lucide-react';

type Props = {
    isOpen: boolean;
    title?: string;
    message?: string;
    onClose: () => void;
    onConfirm: () => void;
    isDeleting?: boolean;
};

export default function DeleteModal({
    isOpen,
    title = 'Confirm Delete',
    message = 'Are you sure you want to delete this record? This action cannot be undone.',
    onClose,
    onConfirm,
    isDeleting = false,
}: Props) {
    if (!isOpen) return null;

    return (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4 backdrop-blur-xs">
            <div className="w-full max-w-sm rounded-3xl bg-white p-6 text-center shadow-2xl transition-all">
                {/* CIRCULAR ICON BADGE */}
                <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-red-50 text-red-600">
                    <Trash2 className="h-6 w-6" />
                </div>

                {/* TITLE & DESCRIPTION */}
                <div className="mt-4 space-y-1.5">
                    <h3 className="text-lg font-bold text-[#0F172A]">{title}</h3>
                    <p className="text-xs font-medium text-gray-500 leading-relaxed">
                        {message}
                    </p>
                </div>

                {/* ACTIONS */}
                <div className="mt-6 grid grid-cols-2 gap-3">
                    <button
                        type="button"
                        onClick={onClose}
                        disabled={isDeleting}
                        className="w-full rounded-xl border border-gray-200 py-2.5 text-xs font-bold text-gray-700 transition hover:bg-gray-50 disabled:opacity-50"
                    >
                        Cancel
                    </button>
                    <button
                        type="button"
                        onClick={onConfirm}
                        disabled={isDeleting}
                        className="w-full rounded-xl bg-red-600 py-2.5 text-xs font-bold text-white transition hover:bg-red-700 active:scale-[0.98] disabled:opacity-50"
                    >
                        {isDeleting ? 'Deleting...' : 'Delete'}
                    </button>
                </div>
            </div>
        </div>
    );
}