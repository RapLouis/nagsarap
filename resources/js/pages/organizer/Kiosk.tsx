import React, { useRef, useState, useEffect, useCallback } from 'react';
import { Head } from '@inertiajs/react';
import OrganizerLayout from '@/layouts/organizer-layout';
import { Dialog, DialogContent } from '@/components/ui/dialog';
import type { FaceLandmarker } from '@mediapipe/tasks-vision';
import { 
  CheckCircle2, 
  AlertCircle, 
  Camera, 
  RefreshCw, 
  UserCheck, 
  Copy, 
  ArrowLeft,
  ArrowRight,
  UserSearch,
  Clock,
  Calendar,
  MapPin,
  ShieldCheck
} from 'lucide-react';
import {
  DIRECTION_SIGN,
  FLASH_CAPTURE_AT_MS,
  FLASH_CSS_COLORS,
  FLASH_DURATION_MS,
  LIVE_FRAME_OPTIONS,
  VIDEO_CONSTRAINTS,
  calculateYaw,
  captureFrameScaled,
  getSharedLandmarker,
} from '@/lib/liveness';
import type { Direction, FlashColor, Landmark } from '@/lib/liveness';
import axios from 'axios';

interface ScheduleSlot {
  time_in_start: string;
  time_in_end: string;
  time_out_start: string;
  time_out_end: string;
}

interface ScheduleItem {
  date: string;
  slots: ScheduleSlot[];
}

interface EventItem {
  id: number;
  title: string;
  location?: string | null;
  event_date?: string;
  event_end_date?: string | null;
  schedules?: ScheduleItem[] | null;
  is_geofenced?: boolean;
  radius_meters?: number;
}

interface RecentScan {
  name: string;
  student_number: string;
  course: string;
  type: string;
  time: string;
}

type Step = 'IDLE' | 'ALIGN' | 'FLASHING' | 'TURN' | 'SUBMITTING' | 'DONE' | 'FAILED';

const PROCESS_EVERY_N_FRAMES = 3;
const FRONTAL_YAW_MAX = 0.12;
const FRONTAL_HOLD_FRAMES = 8;
const FLASH_FRAME_COUNT = 3;
const FLASH_GAP_MS = 150;
const TURN_YAW_MIN = 0.10;
const TURN_YAW_MAX = 0.70;
const TURN_HOLD_FRAMES = 2;
const TURN_TIMEOUT_MS = 20_000;
const NEUTRAL_BG = '#000000';

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

const playAudioCue = (type: 'success' | 'error') => {
  try {
    const ctx = new (window.AudioContext || (window as any).webkitAudioContext)();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.connect(gain);
    gain.connect(ctx.destination);

    if (type === 'success') {
      osc.frequency.setValueAtTime(587.33, ctx.currentTime);
      osc.frequency.setValueAtTime(880, ctx.currentTime + 0.1);
      gain.gain.setValueAtTime(0.1, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.35);
      osc.start(ctx.currentTime);
      osc.stop(ctx.currentTime + 0.35);
    } else {
      osc.frequency.setValueAtTime(220, ctx.currentTime);
      osc.frequency.setValueAtTime(146.83, ctx.currentTime + 0.15);
      gain.gain.setValueAtTime(0.15, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.4);
      osc.start(ctx.currentTime);
      osc.stop(ctx.currentTime + 0.4);
    }
  } catch (e) {
    // AudioContext blocked or unsupported
  }
};

function nextVideoFrame(video: HTMLVideoElement, timeoutMs = 250): Promise<void> {
  return new Promise((resolve) => {
    const target = video as HTMLVideoElement & { requestVideoFrameCallback?: (callback: () => void) => number };
    if (typeof target.requestVideoFrameCallback !== 'function') {
      setTimeout(resolve, 60);
      return;
    }
    const timer = setTimeout(resolve, timeoutMs);
    target.requestVideoFrameCallback(() => { clearTimeout(timer); resolve(); });
  });
}

function inspectFace(landmarker: FaceLandmarker, video: HTMLVideoElement, yawMax = FRONTAL_YAW_MAX): string | null {
  let faces: Landmark[][];
  try {
    faces = landmarker.detectForVideo(video, performance.now()).faceLandmarks ?? [];
  } catch (error) {
    return 'Checking face…';
  }
  if (faces.length === 0) return 'Position student face inside the circle.';
  if (faces.length > 1) return 'Multiple faces detected.';
  const landmarks = faces[0];
  if (Math.abs(calculateYaw(landmarks)) > yawMax) return 'Look straight at camera.';
  return null;
}

export default function Kiosk({ events = [] }: { events: EventItem[] }) {
  const [currentWorkflowStep, setCurrentWorkflowStep] = useState<1 | 2 | 3>(1);
  const [selectedEventId, setSelectedEventId] = useState<number>(events[0]?.id || 0);

  const videoRef = useRef<HTMLVideoElement | null>(null);
  const landmarkerRef = useRef<FaceLandmarker | null>(null);
  const mountedRef = useRef(true);

  const [step, setStep] = useState<Step>('IDLE');
  const [challenge, setChallenge] = useState<{ nonce: string; direction: Direction; flash_colors: string[] } | null>(null);
  const [flashColor, setFlashColor] = useState<FlashColor | null>(null);
  const [hint, setHint] = useState<string | null>(null);
  const [holdProgress, setHoldProgress] = useState(0);
  const [copied, setCopied] = useState(false);
  const [isGeneratingToken, setIsGeneratingToken] = useState(false);
  const [generatedKioskUrl, setGeneratedKioskUrl] = useState<string | null>(null);

  const [recentScans, setRecentScans] = useState<RecentScan[]>([]);

  const [showManualModal, setShowManualModal] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<any[]>([]);
  const [searching, setSearching] = useState(false);

  const frontalBlobRef = useRef<Blob | null>(null);
  const flashBlobsRef = useRef<Blob[]>([]);
  const challengeRef = useRef(challenge);
  challengeRef.current = challenge;

  const [modalResult, setModalResult] = useState<any>({ open: false, success: false, message: '', student: null });

  const selectedEvent = events.find(e => e.id === Number(selectedEventId));

  useEffect(() => {
    mountedRef.current = true;
    let stream: MediaStream | null = null;

    if (currentWorkflowStep === 3) {
      navigator.mediaDevices.getUserMedia(VIDEO_CONSTRAINTS)
        .then((s) => {
          stream = s;
          if (videoRef.current) videoRef.current.srcObject = s;
        })
        .catch((err) => console.error('Camera error:', err));

      getSharedLandmarker().then((landmarker) => {
        if (mountedRef.current) landmarkerRef.current = landmarker;
      }).catch(err => console.error('Model init error:', err));
    }

    return () => {
      mountedRef.current = false;
      if (stream) stream.getTracks().forEach((track) => track.stop());
    };
  }, [currentWorkflowStep]);

  const handleGenerateCoOrganizerLink = async () => {
    if (!selectedEventId) return;
    setIsGeneratingToken(true);
    setTimeout(() => {
      const token = Math.random().toString(36).substring(2, 10);
      const secureUrl = `${window.location.origin}/organizer/kiosk?event_id=${selectedEventId}&token=${token}`;
      setGeneratedKioskUrl(secureUrl);
      setIsGeneratingToken(false);
    }, 400);
  };

  const startScan = async () => {
    if (!selectedEventId || selectedEventId === 0) {
      alert('Please select a valid target event before starting the liveness scan.');
      return;
    }

    try {
      const res = await axios.get('/organizer/kiosk/challenge');
      setChallenge(res.data);
      setStep('ALIGN');
      setHint(null);
    } catch (err) {
      alert('Failed to initialize liveness challenge session.');
    }
  };

  const submitAttendance = useCallback(async (frontal: Blob, flashes: Blob[], peak: Blob) => {
    setStep('SUBMITTING');
    setHint(null);
    setFlashColor(null);

    const formData = new FormData();
    formData.append('event_id', String(selectedEventId));
    formData.append('challenge_nonce', challengeRef.current?.nonce ?? '');
    formData.append('live_camera_frame', frontal, 'frontal.jpg');
    flashes.forEach((blob, index) => formData.append(`flash_frames[${index}]`, blob, `flash_${index}.jpg`));
    formData.append('turn_peak_frame', peak, 'turn-peak.jpg');

    try {
      const response = await axios.post('/organizer/kiosk/verify', formData);
      playAudioCue('success');

      const scanData = {
        name: response.data.student.name,
        student_number: response.data.student.student_number,
        course: response.data.student.course,
        type: response.data.type,
        time: response.data.time_in,
      };

      setRecentScans(prev => [scanData, ...prev.slice(0, 9)]);

      setModalResult({
        open: true,
        success: true,
        message: response.data.message,
        student: response.data.student,
        type: response.data.type,
        time_in: response.data.time_in,
      });
      setStep('DONE');
    } catch (error: any) {
      playAudioCue('error');
      setModalResult({
        open: true,
        success: false,
        message: error.response?.data?.message || 'Facial verification failed.',
      });
      setStep('FAILED');
    }
  }, [selectedEventId]);

  const runSequence = useCallback(async () => {
    const video = videoRef.current;
    const landmarker = landmarkerRef.current;
    const colors = challengeRef.current?.flash_colors ?? [];

    if (!video || !landmarker || colors.length !== FLASH_FRAME_COUNT) return;

    try {
      const baseline = await captureFrameScaled(video, LIVE_FRAME_OPTIONS);
      if (!baseline) return;

      setStep('FLASHING');
      const flashes: Blob[] = [];

      for (const color of colors) {
        setFlashColor(null);
        await sleep(FLASH_GAP_MS);
        setFlashColor(color as FlashColor);
        await sleep(FLASH_CAPTURE_AT_MS);
        await nextVideoFrame(video);

        const blob = await captureFrameScaled(video, LIVE_FRAME_OPTIONS);
        if (blob) flashes.push(blob);
        await sleep(Math.max(FLASH_DURATION_MS - FLASH_CAPTURE_AT_MS, 0));
      }

      frontalBlobRef.current = baseline;
      flashBlobsRef.current = flashes;
      setFlashColor(null);
      setStep('TURN');
    } catch {
      setStep('FAILED');
    }
  }, []);

  useEffect(() => {
    if (step !== 'ALIGN' || !videoRef.current || !landmarkerRef.current) return;
    let stopped = false, raf = 0, stable = 0;

    const tick = () => {
      if (stopped) return;
      const video = videoRef.current;
      const landmarker = landmarkerRef.current;
      if (video && landmarker && video.readyState >= 2) {
        const issue = inspectFace(landmarker, video);
        if (issue) {
          stable = 0;
          setHoldProgress(0);
          setHint(issue);
        } else {
          setHint(null);
          stable += 1;
          setHoldProgress(Math.min(stable / FRONTAL_HOLD_FRAMES, 1));
          if (stable >= FRONTAL_HOLD_FRAMES) {
            stopped = true;
            cancelAnimationFrame(raf);
            void runSequence();
            return;
          }
        }
      }
      if (!stopped) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => { stopped = true; cancelAnimationFrame(raf); };
  }, [step, runSequence]);

  useEffect(() => {
    if (step !== 'TURN' || !videoRef.current || !landmarkerRef.current || !challenge) return;
    let stopped = false, raf = 0, hold = 0;
    const direction = challenge.direction;
    const started = performance.now();

    const tick = () => {
      if (stopped) return;
      const video = videoRef.current;
      const landmarker = landmarkerRef.current;
      if (performance.now() - started > TURN_TIMEOUT_MS) {
        stopped = true;
        setStep('FAILED');
        return;
      }
      if (video && landmarker && video.readyState >= 2) {
        let faces = landmarker.detectForVideo(video, performance.now()).faceLandmarks ?? [];
        if (faces.length === 1) {
          const turned = calculateYaw(faces[0]) * DIRECTION_SIGN[direction];
          if (turned >= TURN_YAW_MIN && turned <= TURN_YAW_MAX) {
            hold += 1;
            if (hold >= TURN_HOLD_FRAMES) {
              stopped = true;
              cancelAnimationFrame(raf);
              captureFrameScaled(video, LIVE_FRAME_OPTIONS).then(peak => {
                if (frontalBlobRef.current && peak) {
                  submitAttendance(frontalBlobRef.current, flashBlobsRef.current, peak);
                }
              });
              return;
            }
          } else {
            hold = 0;
            setHint(`Turn head toward ${direction}`);
          }
        }
      }
      if (!stopped) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => { stopped = true; cancelAnimationFrame(raf); };
  }, [step, challenge, submitAttendance]);

  const handleSearchStudents = async (query: string) => {
    setSearchQuery(query);
    if (query.length < 2) {
      setSearchResults([]);
      return;
    }
    setSearching(true);
    try {
      const res = await axios.get(`/organizer/students/search?q=${encodeURIComponent(query)}`);
      setSearchResults(res.data.students || []);
    } catch (e) {
      console.error(e);
    } finally {
      setSearching(false);
    }
  };

  const handleManualCheckIn = async (studentId: number) => {
    if (!selectedEventId || selectedEventId === 0) {
      alert('Please select an active event first.');
      return;
    }
    try {
      const res = await axios.post('/organizer/kiosk/manual-override', {
        event_id: selectedEventId,
        student_id: studentId,
      });
      playAudioCue('success');
      alert(res.data.message);
      setShowManualModal(false);
      setSearchQuery('');
      setSearchResults([]);
    } catch (err: any) {
      playAudioCue('error');
      alert(err.response?.data?.message || 'Manual override failed.');
    }
  };

  const flashing = step === 'FLASHING';
  const direction = challenge?.direction ?? 'left';
  const TurnIcon = direction === 'left' ? ArrowLeft : ArrowRight;

  return (
    <OrganizerLayout title="Attendance Operations Hub">
      <Head title="Attendance Operations | Organizer Kiosk" />
      
      {/* FULL SCREEN FLASH OVERLAY - COVERS 100% OF WHITE SPACES DURING LIVENESS REFLECTION TESTS */}
      {flashing && (
        <div 
          className="fixed inset-0 z-50 pointer-events-none transition-colors duration-75"
          style={{ backgroundColor: flashColor ? FLASH_CSS_COLORS[flashColor] : NEUTRAL_BG }}
        />
      )}

      <div className="max-w-4xl mx-auto space-y-6 font-sans antialiased text-gray-900">
        
        {/* HEADER & STEP INDICATOR */}
        <div className="bg-white p-5 rounded-2xl border border-gray-200/80 shadow-xs flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div>
            <h1 className="text-xl sm:text-2xl font-black text-[#1B1F5C]">Organizer Attendance Kiosk</h1>
            <p className="text-xs text-gray-500 font-medium">
              {currentWorkflowStep === 1 && 'Step 1: Select an active ongoing event'}
              {currentWorkflowStep === 2 && 'Step 2: Review schedules & generate co-organizer link'}
              {currentWorkflowStep === 3 && 'Step 3: Biometric face scanning attendance mode'}
            </p>
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={() => setShowManualModal(true)}
              className="inline-flex items-center gap-1.5 px-3.5 py-2 bg-amber-500 hover:bg-amber-600 text-white text-xs font-bold rounded-xl transition shadow-xs cursor-pointer"
              title="Manual override fallback search"
            >
              <UserSearch className="w-4 h-4" />
              <span>Manual Override</span>
            </button>
            <div className="flex items-center gap-1.5 text-xs font-bold text-[#1B1F5C] bg-indigo-50 px-3.5 py-2 rounded-xl border border-indigo-100 shrink-0">
              <ShieldCheck className="w-4 h-4 text-[#F5A623]" />
              <span>Step {currentWorkflowStep} of 3</span>
            </div>
          </div>
        </div>

        {/* STEP 1: SELECT ACTIVE ONGOING EVENT */}
        {currentWorkflowStep === 1 && (
          <div className="bg-white p-6 rounded-3xl border border-gray-200/80 shadow-xs space-y-4 animate-fadeIn">
            <div className="flex items-center justify-between pb-3 border-b border-gray-100">
              <h2 className="text-sm font-extrabold text-[#1B1F5C] uppercase tracking-wider">Select Active Ongoing Event</h2>
              <span className="text-xs font-bold text-gray-400">{events.length} available</span>
            </div>

            {events.length === 0 ? (
              <div className="p-12 text-center space-y-3">
                <Calendar className="w-10 h-10 text-gray-300 mx-auto" />
                <p className="text-gray-900 font-bold text-sm">No ongoing events found.</p>
                <p className="text-xs text-gray-500">Events must be approved and active for today to appear on the kiosk.</p>
              </div>
            ) : (
              <div className="grid grid-cols-1 gap-3">
                {events.map((evt) => {
                  const isSelected = selectedEventId === evt.id;
                  return (
                    <div
                      key={evt.id}
                      onClick={() => setSelectedEventId(evt.id)}
                      className={`p-4 rounded-2xl border-2 transition-all cursor-pointer flex items-center justify-between bg-white shadow-2xs ${
                        isSelected ? 'border-[#1B1F5C] bg-indigo-50/40 shadow-xs ring-2 ring-[#1B1F5C]/10' : 'border-gray-200/80 hover:border-gray-300'
                      }`}
                    >
                      <div className="space-y-1">
                        <h3 className="text-base font-black text-[#1B1F5C]">{evt.title}</h3>
                        <div className="flex flex-wrap items-center gap-3 text-xs text-gray-500 font-medium">
                          {evt.location && (
                            <span className="flex items-center gap-1">
                              <MapPin className="h-3.5 w-3.5 text-[#F5A623]" /> {evt.location}
                            </span>
                          )}
                          <span className="flex items-center gap-1">
                            <Calendar className="h-3.5 w-3.5 text-[#1B1F5C]" /> {evt.event_date || 'Today'}
                          </span>
                        </div>
                      </div>
                      <div className={`h-6 w-6 rounded-full border-2 flex items-center justify-center shrink-0 transition-colors ${
                        isSelected ? 'border-[#1B1F5C] bg-[#1B1F5C] text-white' : 'border-gray-300 bg-white'
                      }`}>
                        {isSelected && <CheckCircle2 className="h-4 w-4" />}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}

            <div className="flex justify-end pt-3">
              <button
                type="button"
                disabled={!selectedEventId || selectedEventId === 0}
                onClick={() => setCurrentWorkflowStep(2)}
                className="inline-flex items-center gap-2 min-h-[44px] bg-[#1B1F5C] text-white px-6 py-2.5 rounded-xl font-bold text-xs shadow-md hover:bg-[#131644] disabled:opacity-40 transition cursor-pointer"
              >
                <span>Continue to Event Schedules</span>
                <ArrowRight className="h-4 w-4 text-[#F5A623]" />
              </button>
            </div>
          </div>
        )}

        {/* STEP 2: VIEW TIME SLOTS & GENERATE KIOSK LINK */}
        {currentWorkflowStep === 2 && selectedEvent && (
          <div className="bg-white p-6 rounded-3xl border border-gray-200/80 shadow-xs space-y-6 animate-fadeIn">
            <div className="border-b border-gray-100 pb-4">
              <span className="text-[10px] font-extrabold uppercase tracking-wider text-gray-400">Selected Event Target</span>
              <h2 className="text-xl font-black text-[#1B1F5C] mt-0.5">{selectedEvent.title}</h2>
              {selectedEvent.location && (
                <p className="text-xs text-gray-500 font-medium flex items-center gap-1 mt-1">
                  <MapPin className="h-3.5 w-3.5 text-[#F5A623]" /> {selectedEvent.location}
                </p>
              )}
            </div>

            <div className="space-y-3">
              <h3 className="text-xs font-bold text-gray-700 uppercase tracking-wider flex items-center gap-1.5">
                <Clock className="w-4 h-4 text-[#F5A623]" /> Time-In & Time-Out Windows
              </h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                {selectedEvent.schedules?.[0]?.slots?.length ? (
                  selectedEvent.schedules[0].slots.map((slot, idx) => (
                    <div key={idx} className="bg-gray-50 p-4 rounded-xl border border-gray-200/80 text-xs space-y-1.5">
                      <div className="font-bold text-emerald-700 flex items-center gap-1.5">
                        <span>Time-In:</span>
                        <span>{slot.time_in_start} {slot.time_in_end ? `- ${slot.time_in_end}` : ''}</span>
                      </div>
                      <div className="font-bold text-amber-700 flex items-center gap-1.5">
                        <span>Time-Out:</span>
                        <span>{slot.time_out_start || 'N/A'} {slot.time_out_end ? `- ${slot.time_out_end}` : ''}</span>
                      </div>
                    </div>
                  ))
                ) : (
                  <div className="bg-gray-50 p-4 rounded-xl border border-gray-200/80 text-xs text-gray-500">
                    Standard all-day schedule configured for this event.
                  </div>
                )}
              </div>
            </div>

            <div className="pt-4 border-t border-gray-100 space-y-3">
              <div className="flex items-center justify-between flex-wrap gap-2">
                <div>
                  <h4 className="text-xs font-bold text-gray-900">Generate Co-Organizer Kiosk Link</h4>
                  <p className="text-[11px] text-gray-500">Secure URL for other organizers to run this kiosk on secondary devices.</p>
                </div>
                <button
                  type="button"
                  onClick={handleGenerateCoOrganizerLink}
                  disabled={isGeneratingToken}
                  className="inline-flex items-center gap-1.5 px-3.5 py-2 bg-indigo-50 text-[#1B1F5C] border border-indigo-200 rounded-xl text-xs font-bold hover:bg-indigo-100 transition cursor-pointer"
                >
                  {isGeneratingToken && <RefreshCw className="h-3.5 w-3.5 animate-spin" />}
                  <span>{generatedKioskUrl ? 'Regenerate Link' : 'Generate Kiosk Link'}</span>
                </button>
              </div>

              {generatedKioskUrl && (
                <div className="flex items-center gap-2 bg-gray-50 p-3 rounded-xl border border-gray-200 animate-fadeIn">
                  <input
                    type="text"
                    readOnly
                    value={generatedKioskUrl}
                    className="w-full bg-transparent text-xs font-mono text-gray-700 focus:outline-none"
                  />
                  <button
                    type="button"
                    onClick={() => { navigator.clipboard.writeText(generatedKioskUrl); setCopied(true); setTimeout(() => setCopied(false), 2500); }}
                    className="min-h-[38px] px-4 bg-[#1B1F5C] text-white rounded-lg text-xs font-bold flex items-center gap-1.5 shrink-0 hover:bg-[#131644] cursor-pointer"
                  >
                    <Copy className="h-3.5 w-3.5 text-[#F5A623]" />
                    <span>{copied ? 'Copied!' : 'Copy'}</span>
                  </button>
                </div>
              )}
            </div>

            <div className="flex items-center justify-between pt-3">
              <button
                type="button"
                onClick={() => setCurrentWorkflowStep(1)}
                className="inline-flex items-center gap-1.5 min-h-[44px] bg-white border border-gray-300 text-gray-700 px-4 py-2.5 rounded-xl font-bold text-xs hover:bg-gray-50 transition cursor-pointer"
              >
                <ArrowLeft className="h-4 w-4" />
                <span>Back to Event Selection</span>
              </button>

              <button
                type="button"
                onClick={() => setCurrentWorkflowStep(3)}
                className="inline-flex items-center gap-2 min-h-[44px] bg-[#1B1F5C] text-white px-6 py-2.5 rounded-xl font-bold text-xs shadow-md hover:bg-[#131644] transition cursor-pointer"
              >
                <Camera className="h-4 w-4 text-[#F5A623]" />
                <span>Launch Face Scanner</span>
              </button>
            </div>
          </div>
        )}

        {/* STEP 3: FACE SCANNING ATTENDANCE MODE */}
        {currentWorkflowStep === 3 && (
          <div className="grid grid-cols-1 md:grid-cols-3 gap-5 animate-fadeIn">
            
            {/* SCANNER VIEWPORT */}
            <div className="md:col-span-2 space-y-4">
              <div 
                className="relative rounded-3xl overflow-hidden bg-black aspect-video flex items-center justify-center border-4 border-[#1B1F5C] shadow-md transition-colors duration-200"
              >
                <video ref={videoRef} autoPlay playsInline muted className="w-full h-full object-cover scale-x-[-1]" />

                {!flashing && step !== 'SUBMITTING' && (
                  <div className="absolute inset-0 border-2 border-white/20 pointer-events-none flex items-center justify-center">
                    <div className="w-56 h-72 border-2 border-dashed border-[#F5A623] rounded-full animate-pulse" />
                  </div>
                )}

                {step === 'TURN' && (
                  <div className={`pointer-events-none absolute top-1/2 -translate-y-1/2 rounded-full bg-black/60 p-3 text-white ${direction === 'left' ? 'left-6' : 'right-6'}`}>
                    <TurnIcon className="h-8 w-8 animate-pulse text-[#F5A623]" />
                  </div>
                )}

                {step === 'SUBMITTING' && (
                  <div className="absolute inset-0 flex flex-col items-center justify-center bg-black/80 text-white backdrop-blur-sm z-30">
                    <RefreshCw className="w-8 h-8 animate-spin text-[#F5A623] mb-2" />
                    <span className="text-xs font-bold">Matching Database & Logging Attendance...</span>
                  </div>
                )}

                {step === 'IDLE' && (
                  <button
                    onClick={startScan}
                    disabled={!selectedEventId || selectedEventId === 0}
                    className="absolute bottom-6 z-20 bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 text-white px-7 py-3 rounded-full font-bold text-xs shadow-xl flex items-center gap-2 transition cursor-pointer"
                  >
                    <Camera className="w-4 h-4" />
                    <span>Start Student Scan</span>
                  </button>
                )}

                {step === 'ALIGN' && (
                  <div className="absolute top-4 left-4 bg-black/70 backdrop-blur-md px-3 py-1.5 rounded-full text-white text-[11px] font-bold border border-white/10">
                    {hint || 'Hold still and look straight...'}
                  </div>
                )}
              </div>

              <div className="flex items-center justify-between">
                <button
                  type="button"
                  onClick={() => setCurrentWorkflowStep(2)}
                  className="inline-flex items-center gap-1.5 min-h-[38px] bg-white border border-gray-300 text-gray-700 px-3.5 py-2 rounded-xl font-bold text-xs hover:bg-gray-50 transition cursor-pointer"
                >
                  <ArrowLeft className="h-3.5 w-3.5" />
                  <span>Back to Event Details</span>
                </button>
                <p className="text-xs text-gray-500 font-medium text-right">
                  Active Event: <span className="font-bold text-gray-800">{selectedEvent?.title}</span>
                </p>
              </div>
            </div>

            {/* LIVE RECENT SCANS TICKER */}
            <div className="bg-white p-4 rounded-3xl border border-gray-200/80 shadow-xs flex flex-col h-[360px]">
              <div className="flex items-center justify-between pb-3 border-b border-gray-100">
                <h3 className="text-xs font-extrabold text-[#1B1F5C] uppercase tracking-wider flex items-center gap-1.5">
                  <Clock className="w-4 h-4 text-[#F5A623]" />
                  <span>Recent Scans</span>
                </h3>
                <span className="text-[10px] bg-indigo-50 text-[#1B1F5C] font-bold px-2 py-0.5 rounded-full">{recentScans.length} logged</span>
              </div>

              <div className="flex-1 overflow-y-auto divide-y divide-gray-50 space-y-2 pt-2 pr-1" aria-live="polite">
                {recentScans.map((scan, idx) => (
                  <div key={idx} className="pt-2 pb-1 first:pt-0 text-xs animate-fadeIn">
                    <div className="font-bold text-gray-900 truncate">{scan.name}</div>
                    <div className="flex items-center justify-between text-[11px] text-gray-500 font-mono mt-0.5">
                      <span>{scan.student_number}</span>
                      <span className="text-emerald-700 font-semibold bg-emerald-50 px-1.5 py-0.5 rounded text-[10px]">{scan.time}</span>
                    </div>
                  </div>
                ))}
                {recentScans.length === 0 && (
                  <div className="h-full flex flex-col items-center justify-center text-center text-gray-400 text-xs p-4">
                    <UserCheck className="w-8 h-8 text-gray-300 mb-1" />
                    <span>No scans recorded yet in this session.</span>
                  </div>
                )}
              </div>
            </div>

          </div>
        )}

        {/* MANUAL OVERRIDE FALLBACK MODAL */}
        {showManualModal && (
          <div className="fixed inset-0 z-50 bg-black/40 backdrop-blur-xs flex items-center justify-center p-3 sm:p-4">
            <div className="bg-white rounded-2xl shadow-xl max-w-md w-full p-5 space-y-4 relative border border-gray-200/80 animate-fadeIn">
              <div className="flex items-center justify-between border-b border-gray-100 pb-3">
                <h3 className="text-sm font-black text-[#1B1F5C] flex items-center gap-2">
                  <UserSearch className="w-4 h-4 text-amber-600" />
                  <span>Manual Attendance Override</span>
                </h3>
                <button onClick={() => setShowManualModal(false)} className="text-gray-400 hover:text-gray-600">×</button>
              </div>

              <div className="space-y-3">
                <p className="text-xs text-gray-500">
                  Search student by name or student number to force check-in if face scanning encounters hardware or lighting errors.
                </p>
                <input
                  type="text"
                  value={searchQuery}
                  onChange={(e) => handleSearchStudents(e.target.value)}
                  placeholder="Type student name or ID..."
                  className="w-full rounded-xl border border-gray-300 px-3.5 py-2.5 text-xs font-medium text-gray-900 focus:border-[#1B1F5C]"
                  autoFocus
                />

                <div className="max-h-60 overflow-y-auto divide-y divide-gray-100 border border-gray-100 rounded-xl">
                  {searchResults.map((stu) => (
                    <div key={stu.student_id} className="p-2.5 flex items-center justify-between hover:bg-gray-50 text-xs">
                      <div>
                        <div className="font-bold text-gray-900">{stu.firstname} {stu.surname}</div>
                        <div className="text-[11px] text-gray-500 font-mono">{stu.student_number} &bull; {stu.degree}</div>
                      </div>
                      <button
                        onClick={() => handleManualCheckIn(stu.student_id)}
                        className="px-3 py-1.5 bg-[#1B1F5C] hover:bg-[#131644] text-white text-[11px] font-bold rounded-lg shadow-2xs"
                      >
                        Force Check-In
                      </button>
                    </div>
                  ))}
                  {searchResults.length === 0 && searchQuery.length >= 2 && !searching && (
                    <div className="p-4 text-center text-xs text-gray-400">No students found matching "{searchQuery}".</div>
                  )}
                </div>
              </div>

              <div className="flex justify-end pt-2">
                <button onClick={() => setShowManualModal(false)} className="px-4 py-2 bg-gray-100 text-gray-700 text-xs font-bold rounded-xl">Close</button>
              </div>
            </div>
          </div>
        )}

        {/* RESULT MODAL */}
        <Dialog open={modalResult.open} onOpenChange={(open) => { setModalResult((prev: any) => ({ ...prev, open })); if (!open) setStep('IDLE'); }}>
          <DialogContent className="sm:max-w-md text-center p-6 rounded-3xl">
            {modalResult.success ? (
              <div className="space-y-3 animate-fadeIn">
                <CheckCircle2 className="w-16 h-16 text-emerald-500 mx-auto" />
                <h3 className="text-lg font-bold text-gray-900">{modalResult.student?.name}</h3>
                <p className="text-xs text-gray-500 font-mono">{modalResult.student?.student_number} &bull; {modalResult.student?.course}</p>
                <div className="pt-2 flex items-center justify-center gap-2">
                  <span className="text-xs font-bold text-indigo-700 bg-indigo-50 border border-indigo-200 py-1 px-3 rounded-full">Type: {modalResult.type}</span>
                  <span className="text-xs font-bold text-emerald-700 bg-emerald-50 border border-emerald-200 py-1 px-3 rounded-full">Logged at: {modalResult.time_in}</span>
                </div>
              </div>
            ) : (
              <div className="space-y-3 animate-fadeIn">
                <AlertCircle className="w-16 h-16 text-rose-500 mx-auto" />
                <h3 className="text-base font-bold text-gray-900">Verification Failed</h3>
                <p className="text-xs text-gray-500">{modalResult.message}</p>
              </div>
            )}
          </DialogContent>
        </Dialog>

      </div>
    </OrganizerLayout>
  );
}