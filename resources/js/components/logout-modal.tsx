import React from 'react';
import { Link } from '@inertiajs/react';
import { LogOut } from 'lucide-react';

interface LogoutModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function LogoutModal({ isOpen, onClose }: LogoutModalProps) {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4">
      <div className="w-full max-w-sm rounded-2xl bg-white p-6 shadow-xl transition-all">
        {/* Icon & Title */}
        <div className="flex flex-col items-center text-center">
          <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-red-100 text-red-600">
            <LogOut className="h-6 w-6" />
          </div>
          <h3 className="text-lg font-bold text-gray-900">Confirm Logout</h3>
          <p className="mt-2 text-sm text-gray-500">
            Are you sure you want to log out of your account?
          </p>
        </div>

        {/* Modal Actions */}
        <div className="mt-6 flex gap-3">
          <button
            type="button"
            onClick={onClose}
            className="flex-1 rounded-xl border border-gray-300 px-4 py-2.5 text-sm font-semibold text-gray-700 hover:bg-gray-50 transition"
          >
            Cancel
          </button>

          <Link
            href="/logout"
            method="post"
            as="button"
            className="flex-1 rounded-xl bg-red-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-red-700 transition text-center"
          >
            Log out
          </Link>
        </div>
      </div>
    </div>
  );
}