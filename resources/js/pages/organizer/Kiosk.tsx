import React, { useRef, useState, useEffect } from 'react';
import { Head } from '@inertiajs/react';
import OrganizerLayout from '@/layouts/organizer-layout';
import { Dialog, DialogContent } from '@/components/ui/dialog';
import { CheckCircle2, AlertCircle, Camera, RefreshCw } from 'lucide-react';
import axios from 'axios';

export default function Kiosk({ events }: { events: any[] }) {
  const [selectedEventId, setSelectedEventId] = useState<number>(events[0]?.id || 0);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [verifying, setVerifying] = useState(false);
  const [modalResult, setModalResult] = useState<any>({ open: false, success: false, message: '', student: null });

  useEffect(() => {
    let stream: MediaStream | null = null;
    navigator.mediaDevices.getUserMedia({ video: { width: 1280, height: 720, facingMode: 'user' } })
      .then((s) => {
        stream = s;
        if (videoRef.current) videoRef.current.srcObject = s;
      })
      .catch((err) => console.error('Camera access error:', err));

    return () => {
      if (stream) stream.getTracks().forEach((track) => track.stop());
    };
  }, []);

  const captureAndVerify = async () => {
    if (!videoRef.current || !canvasRef.current || !selectedEventId || verifying) return;

    setVerifying(true);
    const canvas = canvasRef.current;
    const video = videoRef.current;
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
    const imageBase64 = canvas.toDataURL('image/jpeg');

    try {
      const response = await axios.post('/organizer/kiosk/verify', {
        event_id: selectedEventId,
        image: imageBase64,
      });

      setModalResult({
        open: true,
        success: true,
        message: response.data.message,
        student: response.data.student,
        time_in: response.data.time_in,
      });
    } catch (error: any) {
      setModalResult({
        open: true,
        success: false,
        message: error.response?.data?.message || 'Verification failed. Try again.',
      });
    } finally {
      setVerifying(false);
      setTimeout(() => {
        setModalResult({ open: false, success: false, message: '', student: null });
      }, 3500);
    }
  };

  return (
    <OrganizerLayout title="Kiosk Mode">
      <Head title="Facial Recognition Kiosk" />
      <div className="max-w-4xl mx-auto space-y-6">
        <div className="bg-white p-4 rounded-2xl border border-gray-100 shadow-xs flex items-center justify-between">
          <label className="text-sm font-bold text-gray-700">Select Active Event:</label>
          <select
            value={selectedEventId}
            onChange={(e) => setSelectedEventId(Number(e.target.value))}
            className="rounded-xl border border-gray-200 px-4 py-2 text-sm font-medium text-gray-800 focus:border-[#03045E]"
          >
            {events.map((evt) => (
              <option key={evt.id} value={evt.id}>{evt.title}</option>
            ))}
          </select>
        </div>

        <div className="relative rounded-3xl overflow-hidden bg-black aspect-video flex items-center justify-center border-4 border-[#03045E]">
          {/* pointer-events-none ensures video doesn't block button clicks */}
          <video ref={videoRef} autoPlay playsInline muted className="w-full h-full object-cover pointer-events-none" />
          <canvas ref={canvasRef} className="hidden" />

          <div className="absolute inset-0 border-2 border-white/20 pointer-events-none flex items-center justify-center">
            <div className="w-64 h-80 border-2 border-dashed border-white/60 rounded-full" />
          </div>

          <button
            onClick={captureAndVerify}
            disabled={verifying}
            className="absolute bottom-6 z-20 bg-[#03045E] hover:bg-[#1D217D] text-white px-8 py-3 rounded-full font-bold text-sm shadow-lg flex items-center gap-2 transition cursor-pointer disabled:opacity-50"
          >
            {verifying ? <RefreshCw className="w-5 h-5 animate-spin" /> : <Camera className="w-5 h-5" />}
            <span>{verifying ? 'Verifying...' : 'Scan Face'}</span>
          </button>
        </div>

        <Dialog open={modalResult.open} onOpenChange={() => {}}>
          <DialogContent className="sm:max-w-md text-center p-6">
            {modalResult.success ? (
              <div className="space-y-3">
                <CheckCircle2 className="w-16 h-16 text-emerald-500 mx-auto" />
                <h3 className="text-xl font-bold text-gray-900">{modalResult.student?.name}</h3>
                <p className="text-sm text-gray-500">{modalResult.student?.student_number} • {modalResult.student?.course}</p>
                <p className="text-xs font-semibold text-emerald-600 bg-emerald-50 py-1 px-3 rounded-full inline-block">
                  Time-In: {modalResult.time_in}
                </p>
              </div>
            ) : (
              <div className="space-y-3">
                <AlertCircle className="w-16 h-16 text-rose-500 mx-auto" />
                <h3 className="text-lg font-bold text-gray-900">Verification Failed</h3>
                <p className="text-sm text-gray-500">{modalResult.message}</p>
              </div>
            )}
          </DialogContent>
        </Dialog>
      </div>
    </OrganizerLayout>
  );
}