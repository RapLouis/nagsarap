import React, { useState } from 'react';
import { Head, useForm } from '@inertiajs/react';
import { KeyRound, Eye, EyeOff, ShieldCheck, Check, AlertCircle } from 'lucide-react';

export default function FirstTimeChangePassword() {
  const [showPass, setShowPass] = useState(false);
  const [showConfirmPass, setShowConfirmPass] = useState(false);

  const { data, setData, post, processing, errors } = useForm({
    password: '',
    password_confirmation: '',
  });

  // Calculate basic password strength for visual feedback
  const getStrength = (pass: string) => {
    let score = 0;
    if (pass.length >= 8) score++;
    if (/[A-Z]/.test(pass)) score++;
    if (/[0-9]/.test(pass) || /[^A-Za-z0-9]/.test(pass)) score++;
    return score;
  };

  const strengthScore = getStrength(data.password);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    post('/first-time-change-password');
  };

  return (
    <>
      <Head title="First-Time Password Setup | 4ttnd" />

      <div className="min-h-screen bg-[#F5F6FA] flex flex-col justify-center items-center p-4 font-sans text-gray-900 antialiased">
        <div className="bg-white rounded-2xl shadow-xl max-w-md w-full p-6 sm:p-7 space-y-6 border border-gray-200/80">
          
          {/* Header Banner */}
          <div className="flex items-start gap-3.5 border-b border-gray-100 pb-4">
            <div className="p-3 bg-amber-50 text-amber-600 rounded-xl border border-amber-200/70 shrink-0">
              <KeyRound className="w-6 h-6" aria-hidden="true" />
            </div>
            <div>
              <h1 className="text-lg font-black text-[#1B1F5C] tracking-tight">
                Change Temporary Password
              </h1>
              <p className="text-xs text-gray-500 font-medium mt-0.5 leading-relaxed">
                For security reasons, please set a new personal password before accessing your workspace.
              </p>
            </div>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            {/* New Password Input */}
            <div>
              <label htmlFor="password" className="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">
                New Password <span className="text-rose-500">*</span>
              </label>
              <div className="relative">
                <input
                  id="password"
                  type={showPass ? 'text' : 'password'}
                  value={data.password}
                  onChange={e => setData('password', e.target.value)}
                  placeholder="Enter your new password"
                  autoComplete="new-password"
                  className="w-full min-h-[44px] rounded-xl border border-gray-300 text-xs sm:text-sm p-2.5 pr-10 text-gray-900 bg-white focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] focus-visible:outline-none shadow-xs transition-all"
                  required
                />
                <button
                  type="button"
                  onClick={() => setShowPass(!showPass)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-[#1B1F5C] p-1 rounded-md focus-visible:ring-2 focus-visible:ring-[#F5A623] transition-colors"
                  aria-label={showPass ? 'Hide password' : 'Show password'}
                >
                  {showPass ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>

              {/* Password Strength Indicator Meter */}
              {data.password.length > 0 && (
                <div className="mt-2 space-y-1.5">
                  <div className="flex gap-1 h-1.5 w-full bg-gray-100 rounded-full overflow-hidden">
                    <div className={`h-full flex-1 transition-all duration-300 ${strengthScore >= 1 ? 'bg-rose-500' : 'bg-transparent'}`} />
                    <div className={`h-full flex-1 transition-all duration-300 ${strengthScore >= 2 ? 'bg-amber-400' : 'bg-transparent'}`} />
                    <div className={`h-full flex-1 transition-all duration-300 ${strengthScore >= 3 ? 'bg-emerald-500' : 'bg-transparent'}`} />
                  </div>
                  <div className="flex justify-between items-center text-[10px] font-bold text-gray-400">
                    <span>Strength:</span>
                    <span className={
                      strengthScore === 1 ? 'text-rose-500' :
                      strengthScore === 2 ? 'text-amber-600' :
                      strengthScore === 3 ? 'text-emerald-600' : 'text-gray-400'
                    }>
                      {strengthScore === 1 ? 'Weak' : strengthScore === 2 ? 'Medium' : strengthScore === 3 ? 'Strong' : ''}
                    </span>
                  </div>
                </div>
              )}

              {errors.password && (
                <div className="flex items-center gap-1.5 text-rose-600 text-xs mt-1.5 font-bold">
                  <AlertCircle className="w-3.5 h-3.5 shrink-0" />
                  <span>{errors.password}</span>
                </div>
              )}
            </div>

            {/* Confirm Password Input */}
            <div>
              <label htmlFor="password_confirmation" className="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">
                Confirm New Password <span className="text-rose-500">*</span>
              </label>
              <div className="relative">
                <input
                  id="password_confirmation"
                  type={showConfirmPass ? 'text' : 'password'}
                  value={data.password_confirmation}
                  onChange={e => setData('password_confirmation', e.target.value)}
                  placeholder="Re-enter your new password"
                  autoComplete="new-password"
                  className="w-full min-h-[44px] rounded-xl border border-gray-300 text-xs sm:text-sm p-2.5 pr-10 text-gray-900 bg-white focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] focus-visible:outline-none shadow-xs transition-all"
                  required
                />
                <button
                  type="button"
                  onClick={() => setShowConfirmPass(!showConfirmPass)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-[#1B1F5C] p-1 rounded-md focus-visible:ring-2 focus-visible:ring-[#F5A623] transition-colors"
                  aria-label={showConfirmPass ? 'Hide confirm password' : 'Show confirm password'}
                >
                  {showConfirmPass ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>

              {/* Password Matching Feedback */}
              {data.password_confirmation.length > 0 && (
                <div className="mt-1.5">
                  {data.password === data.password_confirmation ? (
                    <span className="inline-flex items-center gap-1 text-[11px] font-bold text-emerald-600">
                      <Check className="w-3.5 h-3.5" /> Passwords match
                    </span>
                  ) : (
                    <span className="inline-flex items-center gap-1 text-[11px] font-bold text-rose-500">
                      Passwords do not match
                    </span>
                  )}
                </div>
              )}
            </div>

            {/* Submit Button */}
            <button
              type="submit"
              disabled={processing}
              className="w-full min-h-[44px] px-5 py-2.5 bg-[#1B1F5C] hover:bg-[#131644] active:scale-[0.99] text-white rounded-xl text-xs font-bold transition-all focus-visible:ring-2 focus-visible:ring-[#F5A623] shadow-md flex items-center justify-center gap-2 disabled:opacity-50 mt-3"
            >
              <ShieldCheck className="w-4 h-4 text-[#FFD600]" aria-hidden="true" />
              <span>Update Password & Continue</span>
            </button>
          </form>
        </div>
      </div>
    </>
  );
}