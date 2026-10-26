import React, { useState } from 'react';
import { Head, useForm, router } from '@inertiajs/react';
import AdminLayout from '@/layouts/admin-layout';
import { 
  Key, 
  ShieldCheck, 
  UserCheck, 
  UserX, 
  Plus, 
  CheckCircle, 
  X,
  Search,
  Filter,
  Eye,
  EyeOff,
  Copy
} from 'lucide-react';

interface OrganizerKey {
  id: number;
  key_name: string;
  org_code: string;
  plain_secret?: string;
  department: string | null;
  max_uses: number;
  uses_count: number;
  expires_at: string | null;
  is_active: boolean;
  created_at: string;
}

interface OrganizerApplication {
  id: number;
  user_id: number;
  organization_name: string;
  position: string;
  justification: string | null;
  status: 'pending' | 'approved' | 'rejected';
  rejection_reason: string | null;
  created_at: string;
  user: {
    id: number;
    name: string;
    email: string;
    student?: {
      student_id: string;
      degree: string;
      year_section: string;
    };
  };
  key?: {
    org_code: string;
    key_name: string;
  };
}

interface Props {
  keys: OrganizerKey[];
  applications: OrganizerApplication[];
  flash?: {
    success?: string;
    error?: string;
  };
}

export default function OrganizerKeys({ keys = [], applications = [], flash }: Props) {
  const [activeTab, setActiveTab] = useState<'keys' | 'applications'>('keys');
  const [searchQuery, setSearchQuery] = useState('');
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [rejectingAppId, setRejectingAppId] = useState<number | null>(null);
  
  // Track visibility state for each key row
  const [visibleKeys, setVisibleKeys] = useState<{ [id: number]: boolean }>({});

  const toggleKeyVisibility = (id: number) => {
    setVisibleKeys((prev) => ({ ...prev, [id]: !prev[id] }));
  };

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
  };

  // Form for Key Generation
  const { data, setData, post, processing, errors, reset } = useForm({
    key_name: '',
    org_code: '',
    department: '',
    max_uses: 1,
    expires_at: '',
  });

  const rejectionForm = useForm({
    rejection_reason: '',
  });

  const handleCreateKey = (e: React.FormEvent) => {
    e.preventDefault();
    post('/admin/organizer-keys', {
      onSuccess: () => {
        reset();
        setShowCreateModal(false);
      },
    });
  };

  const handleToggleKey = (keyId: number) => {
    router.patch(`/admin/organizer-keys/${keyId}/toggle`);
  };

  const handleApprove = (appId: number) => {
    if (confirm('Are you sure you want to approve this student as an Organizer?')) {
      router.post(`/admin/organizer-applications/${appId}/approve`);
    }
  };

  const handleRejectSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!rejectingAppId) return;

    rejectionForm.post(`/admin/organizer-applications/${rejectingAppId}/reject`, {
      onSuccess: () => {
        setRejectingAppId(null);
        rejectionForm.reset();
      },
    });
  };

  // Filtered lists for Search Bar
  const filteredKeys = keys.filter((k) =>
    k.key_name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    k.org_code.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const filteredApplications = applications.filter((a) =>
    a.user?.name?.toLowerCase().includes(searchQuery.toLowerCase()) ||
    a.organization_name?.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const activeKeyCount = keys.filter(k => k.is_active && k.uses_count < k.max_uses).length;
  const pendingAppsCount = applications.filter(a => a.status === 'pending').length;

  return (
    <>
      <Head title="Organizer Keys" />

      <div className="space-y-6">
        
        {/* Page Title & Subtitle */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div>
            <h1 className="text-xl font-bold text-slate-900">
              Organizer Authorization
            </h1>
            <p className="text-xs text-gray-400 mt-0.5">
              Generate key pairs and manage student organizer access applications.
            </p>
          </div>
          <button
            onClick={() => setShowCreateModal(true)}
            className="inline-flex items-center gap-2 px-4 py-2.5 bg-[#03045E] hover:bg-[#1D217D] text-white text-xs font-semibold rounded-xl shadow-xs transition active:scale-98"
          >
            <Plus className="w-4 h-4" />
            Generate Key Pair
          </button>
        </div>

        {/* Success Alert */}
        {flash?.success && (
          <div className="p-4 bg-emerald-50 border border-emerald-100 text-emerald-800 rounded-2xl flex items-center gap-3 text-xs font-medium">
            <CheckCircle className="w-4 h-4 text-emerald-600 shrink-0" />
            <p>{flash.success}</p>
          </div>
        )}

        {/* STATS CARDS ROW */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-5">
          <div className="bg-white p-6 rounded-2xl border border-gray-100 shadow-xs flex items-center gap-4">
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-indigo-50 text-[#03045E] shrink-0">
              <Key className="h-6 w-6" />
            </div>
            <div>
              <span className="text-[10px] font-bold uppercase tracking-wider text-gray-400 block">Total Key Pairs</span>
              <span className="text-2xl font-bold text-slate-900">{keys.length}</span>
            </div>
          </div>

          <div className="bg-white p-6 rounded-2xl border border-gray-100 shadow-xs flex items-center gap-4">
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-emerald-50 text-emerald-600 shrink-0">
              <CheckCircle className="h-6 w-6" />
            </div>
            <div>
              <span className="text-[10px] font-bold uppercase tracking-wider text-gray-400 block">Active Keys</span>
              <span className="text-2xl font-bold text-slate-900">{activeKeyCount}</span>
            </div>
          </div>

          <div className="bg-white p-6 rounded-2xl border border-gray-100 shadow-xs flex items-center gap-4">
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-amber-50 text-amber-600 shrink-0">
              <ShieldCheck className="h-6 w-6" />
            </div>
            <div>
              <span className="text-[10px] font-bold uppercase tracking-wider text-gray-400 block">Pending Applications</span>
              <span className="text-2xl font-bold text-slate-900">{pendingAppsCount}</span>
            </div>
          </div>
        </div>

        {/* FILTER & SEARCH BAR CARD */}
        <div className="bg-white p-4 rounded-2xl border border-gray-100 shadow-xs flex flex-col md:flex-row items-center justify-between gap-4">
          <div className="flex items-center gap-2">
            <Filter className="w-4 h-4 text-gray-400 ml-2" />
            <span className="text-xs font-bold text-gray-400 uppercase tracking-wider">Tab:</span>
            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => setActiveTab('keys')}
                className={`px-3 py-1.5 rounded-xl text-xs font-semibold transition ${
                  activeTab === 'keys'
                    ? 'bg-[#03045E] text-white shadow-xs'
                    : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                }`}
              >
                Key Pairs ({keys.length})
              </button>
              <button
                type="button"
                onClick={() => setActiveTab('applications')}
                className={`px-3 py-1.5 rounded-xl text-xs font-semibold transition ${
                  activeTab === 'applications'
                    ? 'bg-[#03045E] text-white shadow-xs'
                    : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                }`}
              >
                Applications ({applications.length})
              </button>
            </div>
          </div>

          <div className="relative w-full md:w-72">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Search keys or students..."
              className="w-full pl-9 pr-4 py-2 bg-gray-50/50 rounded-xl border border-gray-200 text-xs text-slate-900 placeholder:text-gray-400 focus:bg-white focus:outline-hidden focus:ring-1 focus:ring-[#03045E]"
            />
          </div>
        </div>

        {/* TAB 1: KEY PAIRS TABLE WITH SECRET KEY TOGGLE */}
        {activeTab === 'keys' && (
          <div className="bg-white rounded-2xl border border-gray-100 shadow-xs overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-left text-xs">
                <thead className="bg-gray-50/60 text-gray-400 font-bold uppercase tracking-wider border-b border-gray-100">
                  <tr>
                    <th className="px-6 py-4">Key Name & Dept</th>
                    <th className="px-6 py-4">Org Code</th>
                    <th className="px-6 py-4">Secret Key</th>
                    <th className="px-6 py-4">Usage Limit</th>
                    <th className="px-6 py-4">Status</th>
                    <th className="px-6 py-4 text-right">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {filteredKeys.map((k) => {
                    const isRevealed = visibleKeys[k.id];
                    return (
                      <tr key={k.id} className="hover:bg-gray-50/50 transition">
                        <td className="px-6 py-4">
                          <div className="font-bold text-slate-900">{k.key_name}</div>
                          <div className="text-[11px] text-gray-400 mt-0.5">{k.department || 'All Departments'}</div>
                        </td>
                        <td className="px-6 py-4 font-mono font-bold text-[#03045E]">
                          {k.org_code}
                        </td>
                        {/* SECRET KEY COLUMN WITH EYE TOGGLE */}
                        <td className="px-6 py-4 font-mono text-slate-900">
                          <div className="flex items-center gap-2">
                            <span className="font-bold tracking-wider">
                              {isRevealed ? k.plain_secret : '••••••••••••'}
                            </span>
                            <button
                              type="button"
                              onClick={() => toggleKeyVisibility(k.id)}
                              className="text-gray-400 hover:text-[#03045E] transition p-1"
                              title={isRevealed ? 'Hide Secret Key' : 'Reveal Secret Key'}
                            >
                              {isRevealed ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
                            </button>
                            {isRevealed && k.plain_secret && (
                              <button
                                type="button"
                                onClick={() => copyToClipboard(k.plain_secret!)}
                                className="text-gray-400 hover:text-emerald-600 transition p-1"
                                title="Copy Secret Key"
                              >
                                <Copy className="w-3.5 h-3.5" />
                              </button>
                            )}
                          </div>
                        </td>
                        <td className="px-6 py-4 font-mono text-gray-600">
                          {k.uses_count} / {k.max_uses} used
                        </td>
                        <td className="px-6 py-4">
                          <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-[11px] font-semibold ${
                            k.is_active && k.uses_count < k.max_uses
                              ? 'bg-emerald-50 text-emerald-700 border border-emerald-200/60'
                              : 'bg-rose-50 text-rose-700 border border-rose-200/60'
                          }`}>
                            <span className={`h-1.5 w-1.5 rounded-full ${k.is_active && k.uses_count < k.max_uses ? 'bg-emerald-500' : 'bg-rose-500'}`} />
                            {k.is_active && k.uses_count < k.max_uses ? 'Active' : 'Disabled'}
                          </span>
                        </td>
                        <td className="px-6 py-4 text-right">
                          <button
                            onClick={() => handleToggleKey(k.id)}
                            className="text-xs font-semibold text-gray-500 hover:text-[#03045E] transition"
                          >
                            {k.is_active ? 'Disable Key' : 'Enable Key'}
                          </button>
                        </td>
                      </tr>
                    );
                  })}
                  {filteredKeys.length === 0 && (
                    <tr>
                      <td colSpan={6} className="px-6 py-12 text-center text-gray-400 italic">
                        No organizer key pairs found.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {/* TAB 2: APPLICATIONS QUEUE */}
        {activeTab === 'applications' && (
          <div className="bg-white rounded-2xl border border-gray-100 shadow-xs overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-left text-xs">
                <thead className="bg-gray-50/60 text-gray-400 font-bold uppercase tracking-wider border-b border-gray-100">
                  <tr>
                    <th className="px-6 py-4">Student Info</th>
                    <th className="px-6 py-4">Applied Org & Position</th>
                    <th className="px-6 py-4">Matched Key</th>
                    <th className="px-6 py-4">Status</th>
                    <th className="px-6 py-4 text-right">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {filteredApplications.map((app) => (
                    <tr key={app.id} className="hover:bg-gray-50/50 transition">
                      <td className="px-6 py-4">
                        <div className="font-bold text-slate-900">{app.user?.name}</div>
                        <div className="text-[11px] text-gray-400 mt-0.5">
                          {app.user?.student?.student_id} &bull; {app.user?.student?.degree}
                        </div>
                      </td>
                      <td className="px-6 py-4">
                        <div className="font-semibold text-slate-800">{app.organization_name}</div>
                        <div className="text-[11px] text-gray-400 mt-0.5">{app.position}</div>
                      </td>
                      <td className="px-6 py-4 font-mono text-[11px] font-bold text-[#03045E]">
                        {app.key?.org_code || 'N/A'}
                      </td>
                      <td className="px-6 py-4">
                        <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-[11px] font-semibold capitalize ${
                          app.status === 'approved'
                            ? 'bg-emerald-50 text-emerald-700 border border-emerald-200/60'
                            : app.status === 'rejected'
                            ? 'bg-rose-50 text-rose-700 border border-rose-200/60'
                            : 'bg-amber-50 text-amber-700 border border-amber-200/60'
                        }`}>
                          {app.status}
                        </span>
                      </td>
                      <td className="px-6 py-4 text-right space-x-2">
                        {app.status === 'pending' && (
                          <>
                            <button
                              onClick={() => handleApprove(app.id)}
                              className="inline-flex items-center gap-1 px-3 py-1.5 bg-emerald-600 text-white rounded-xl text-[11px] font-semibold hover:bg-emerald-700 transition"
                            >
                              <UserCheck className="w-3.5 h-3.5" />
                              Approve
                            </button>
                            <button
                              onClick={() => setRejectingAppId(app.id)}
                              className="inline-flex items-center gap-1 px-3 py-1.5 bg-rose-600 text-white rounded-xl text-[11px] font-semibold hover:bg-rose-700 transition"
                            >
                              <UserX className="w-3.5 h-3.5" />
                              Reject
                            </button>
                          </>
                        )}
                      </td>
                    </tr>
                  ))}
                  {filteredApplications.length === 0 && (
                    <tr>
                      <td colSpan={5} className="px-6 py-12 text-center text-gray-400 italic">
                        No applications found.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {/* CREATE KEY MODAL */}
        {showCreateModal && (
          <div className="fixed inset-0 z-50 bg-black/40 backdrop-blur-xs flex items-center justify-center p-4">
            <div className="bg-white rounded-2xl shadow-xl max-w-md w-full p-6 space-y-4 relative border border-gray-100">
              <button
                onClick={() => setShowCreateModal(false)}
                type="button"
                className="absolute top-4 right-4 text-gray-400 hover:text-gray-600 p-1"
              >
                <X className="w-5 h-5" />
              </button>

              <h3 className="text-base font-bold text-slate-900 border-b border-gray-100 pb-3">
                Generate Organizer Key Pair
              </h3>

              <form onSubmit={handleCreateKey} className="space-y-4 pt-1">
                <div>
                  <label className="block text-xs font-semibold text-gray-700">Key Identifier Name</label>
                  <input
                    type="text"
                    value={data.key_name}
                    onChange={e => setData('key_name', e.target.value)}
                    placeholder="e.g. CS Society Executive Key"
                    className="mt-1 w-full rounded-xl border border-gray-200 text-xs p-2.5 text-slate-900 bg-white placeholder:text-gray-400 focus:ring-1 focus:ring-[#03045E]"
                    required
                  />
                  {errors.key_name && <p className="text-rose-500 text-[10px] mt-1">{errors.key_name}</p>}
                </div>

                <div>
                  <label className="block text-xs font-semibold text-gray-700">Organization Code (Public)</label>
                  <input
                    type="text"
                    value={data.org_code}
                    onChange={e => setData('org_code', e.target.value.toUpperCase())}
                    placeholder="e.g. ORG-CS-2026"
                    className="mt-1 w-full rounded-xl border border-gray-200 text-xs font-mono uppercase p-2.5 text-slate-900 bg-white placeholder:text-gray-400 focus:ring-1 focus:ring-[#03045E]"
                    required
                  />
                  {errors.org_code && <p className="text-rose-500 text-[10px] mt-1">{errors.org_code}</p>}
                </div>

                <div>
                  <label className="block text-xs font-semibold text-gray-700">Department Scope (Optional)</label>
                  <input
                    type="text"
                    value={data.department}
                    onChange={e => setData('department', e.target.value)}
                    placeholder="e.g. College of Computing"
                    className="mt-1 w-full rounded-xl border border-gray-200 text-xs p-2.5 text-slate-900 bg-white placeholder:text-gray-400 focus:ring-1 focus:ring-[#03045E]"
                  />
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-xs font-semibold text-gray-700">Max Allowed Uses</label>
                    <input
                      type="number"
                      min={1}
                      value={data.max_uses}
                      onChange={e => setData('max_uses', parseInt(e.target.value))}
                      className="mt-1 w-full rounded-xl border border-gray-200 text-xs p-2.5 text-slate-900 bg-white placeholder:text-gray-400 focus:ring-1 focus:ring-[#03045E]"
                      required
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-semibold text-gray-700">Expires At (Optional)</label>
                    <input
                      type="date"
                      value={data.expires_at}
                      onChange={e => setData('expires_at', e.target.value)}
                      className="mt-1 w-full rounded-xl border border-gray-200 text-xs p-2.5 text-slate-900 bg-white placeholder:text-gray-400 focus:ring-1 focus:ring-[#03045E]"
                    />
                  </div>
                </div>

                <div className="flex justify-end gap-3 pt-4 border-t border-gray-100">
                  <button
                    type="button"
                    onClick={() => setShowCreateModal(false)}
                    className="px-4 py-2 text-xs font-semibold text-gray-500 hover:text-gray-700"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={processing}
                    className="px-4 py-2 bg-[#03045E] hover:bg-[#1D217D] text-white rounded-xl text-xs font-semibold transition disabled:opacity-50"
                  >
                    Generate Pair
                  </button>
                </div>
              </form>
            </div>
          </div>
        )}

        {/* REJECT REASON MODAL */}
        {rejectingAppId && (
          <div className="fixed inset-0 z-50 bg-black/40 backdrop-blur-xs flex items-center justify-center p-4">
            <div className="bg-white rounded-2xl shadow-xl max-w-md w-full p-6 space-y-4 relative border border-gray-100">
              <button
                onClick={() => setRejectingAppId(null)}
                type="button"
                className="absolute top-4 right-4 text-gray-400 hover:text-gray-600 p-1"
              >
                <X className="w-5 h-5" />
              </button>

              <h3 className="text-base font-bold text-slate-900 border-b border-gray-100 pb-3">
                Reject Organizer Application
              </h3>

              <form onSubmit={handleRejectSubmit} className="space-y-4 pt-1">
                <div>
                  <label className="block text-xs font-semibold text-gray-700">Reason for Rejection</label>
                  <textarea
                    value={rejectionForm.data.rejection_reason}
                    onChange={e => rejectionForm.setData('rejection_reason', e.target.value)}
                    placeholder="Provide a brief explanation for the applicant..."
                    className="mt-1 w-full rounded-xl border border-gray-200 text-xs p-2.5 text-slate-900 bg-white placeholder:text-gray-400 focus:ring-1 focus:ring-[#03045E]"
                    rows={3}
                    required
                  />
                </div>

                <div className="flex justify-end gap-3 pt-2">
                  <button
                    type="button"
                    onClick={() => setRejectingAppId(null)}
                    className="px-4 py-2 text-xs font-semibold text-gray-500 hover:text-gray-700"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={rejectionForm.processing}
                    className="px-4 py-2 bg-rose-600 hover:bg-rose-700 text-white rounded-xl text-xs font-semibold transition disabled:opacity-50"
                  >
                    Confirm Rejection
                  </button>
                </div>
              </form>
            </div>
          </div>
        )}
      </div>
    </>
  );
}

OrganizerKeys.layout = (page: React.ReactNode) => (
  <AdminLayout title="Organizer Keys">{page}</AdminLayout>
);