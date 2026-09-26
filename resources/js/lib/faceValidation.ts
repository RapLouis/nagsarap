// resources/js/lib/faceValidation.ts

// ============================================================================
// ⚙️ FACE VALIDATION CONFIGURATION
// ============================================================================
export const FACE_VAL_CONFIG = {
    BLUR_THRESHOLD: 8,                  // Safe threshold for downscaled images
    MIN_DETECTION_CONFIDENCE: 0.50,
    MIN_FACE_WIDTH_RATIO: 0.10,
    MIN_KEYPOINTS_COUNT: 4,
    WASM_LOCATION: '/mediapipe',
    MODEL_PATH: '/mediapipe/blaze_face_short_range.tflite',
    MESSAGES: {
        TOO_BLURRY: 'Photo is too blurry. Please upload a crisp, well-lit photo.',
        NO_FACE: 'No clear human face detected. Ensure your face is centered and fully visible.',
        MULTIPLE_FACES: 'Multiple faces detected. Please upload a photo with only yourself.',
        TOO_FAR: 'Face is too far away. Please move closer or crop the image.',
        FACE_OBSTRUCTED: 'Face is partially covered or turned away. Please look directly at the camera.',
        GENERAL_ERROR: 'Could not verify face quality. Please upload a clearer portrait photo.',
        INVALID_FILE: 'Invalid or corrupt image file uploaded.',
    },
};

let faceDetectorPromise: Promise<any> | null = null;

/**
 * Pre-loads the MediaPipe face detector model in the background.
 * Call this inside your React component's useEffect() on page mount 
 * so mobile users experience zero loading delay when they pick a photo.
 */
export function preloadFaceDetector(): Promise<any> {
    if (!faceDetectorPromise) {
        faceDetectorPromise = (async () => {
            const { FaceDetector, FilesetResolver } = await import('@mediapipe/tasks-vision');
            const vision = await FilesetResolver.forVisionTasks(FACE_VAL_CONFIG.WASM_LOCATION);

            return FaceDetector.createFromOptions(vision, {
                baseOptions: {
                    modelAssetPath: FACE_VAL_CONFIG.MODEL_PATH,
                    delegate: 'GPU', // Automatically falls back to CPU if unavailable
                },
                runningMode: 'IMAGE',
                minDetectionConfidence: FACE_VAL_CONFIG.MIN_DETECTION_CONFIDENCE,
            });
        })().catch((err) => {
            faceDetectorPromise = null; // Reset promise if loading failed so it can retry
            throw err;
        });
    }
    return faceDetectorPromise;
}

async function getFaceDetector() {
    return preloadFaceDetector();
}

/**
 * Downscale image to a max dimension (512px) to make mobile processing instantaneous 
 * and prevent memory crashes on high-megapixel phone cameras.
 */
function downscaleImage(imageElement: HTMLImageElement, maxDim = 512): HTMLCanvasElement {
    const canvas = document.createElement('canvas');
    let width = imageElement.naturalWidth || imageElement.width;
    let height = imageElement.naturalHeight || imageElement.height;

    if (width > height) {
        if (width > maxDim) {
            height = Math.round((height * maxDim) / width);
            width = maxDim;
        }
    } else {
        if (height > maxDim) {
            width = Math.round((width * maxDim) / height);
            height = maxDim;
        }
    }

    canvas.width = width;
    canvas.height = height;
    // alpha: false boosts canvas rendering performance
    const ctx = canvas.getContext('2d', { alpha: false });
    ctx?.drawImage(imageElement, 0, 0, width, height);
    return canvas;
}

function checkBlurriness(canvas: HTMLCanvasElement, threshold = FACE_VAL_CONFIG.BLUR_THRESHOLD): { isBlurry: boolean; score: number } {
    // willReadFrequently: true optimizes pixel data extraction for mobile browsers
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    if (!ctx) return { isBlurry: true, score: 0 };

    const width = canvas.width;
    const height = canvas.height;
    const imageData = ctx.getImageData(0, 0, width, height);
    const data = imageData.data;

    let sum = 0;
    let sumSq = 0;
    let count = 0;

    // OPTIMIZATION: Step size 2 cuts pixel iteration workload by ~75% for lightning-fast mobile execution
    for (let y = 1; y < height - 1; y += 2) {
        for (let x = 1; x < width - 1; x += 2) {
            const idx = (y * width + x) * 4;
            const center = data[idx] * 0.299 + data[idx + 1] * 0.587 + data[idx + 2] * 0.114;

            const left = data[idx - 4] * 0.299 + data[idx - 3] * 0.587 + data[idx - 2] * 0.114;
            const right = data[idx + 4] * 0.299 + data[idx + 5] * 0.587 + data[idx + 6] * 0.114;
            const top = data[idx - width * 4] * 0.299 + data[idx - width * 4 + 1] * 0.587 + data[idx - width * 4 + 2] * 0.114;
            const bottom = data[idx + width * 4] * 0.299 + data[idx + width * 4 + 1] * 0.587 + data[idx + width * 4 + 2] * 0.114;

            const laplacian = Math.abs(4 * center - left - right - top - bottom);
            sum += laplacian;
            sumSq += laplacian * laplacian;
            count++;
        }
    }

    if (count === 0) return { isBlurry: true, score: 0 };

    const mean = sum / count;
    const variance = sumSq / count - mean * mean;

    return {
        isBlurry: variance < threshold,
        score: variance,
    };
}

/**
 * Validate image & extract standardized normalized keypoint embeddings
 */
export async function validateFaceImage(file: File): Promise<{ 
    isValid: boolean; 
    message?: string; 
    embedding?: { x: number; y: number }[] 
}> {
    return new Promise((resolve) => {
        const img = new Image();
        img.src = URL.createObjectURL(file);

        img.onload = async () => {
            try {
                // 1. Downscale image immediately to max 512px for instant mobile performance
                const processedCanvas = downscaleImage(img, 512);

                // 2. Sharpness / Blurriness Check on downscaled canvas
                const blurResult = checkBlurriness(processedCanvas);
                if (blurResult.isBlurry) {
                    URL.revokeObjectURL(img.src);
                    return resolve({
                        isValid: false,
                        message: FACE_VAL_CONFIG.MESSAGES.TOO_BLURRY,
                    });
                }

                // 3. MediaPipe Face Count Check
                const detector = await getFaceDetector();
                const detectionResult = detector.detect(processedCanvas);
                const faces = detectionResult.detections;

                URL.revokeObjectURL(img.src);

                if (faces.length === 0) {
                    return resolve({
                        isValid: false,
                        message: FACE_VAL_CONFIG.MESSAGES.NO_FACE,
                    });
                }

                if (faces.length > 1) {
                    return resolve({
                        isValid: false,
                        message: FACE_VAL_CONFIG.MESSAGES.MULTIPLE_FACES,
                    });
                }

                // 4. Quality Checks
                const detectedFace = faces[0];
                const boundingBox = detectedFace.boundingBox;

                const imgWidth = processedCanvas.width;
                const imgHeight = processedCanvas.height;

                const faceWidthRatio = boundingBox.width / imgWidth;
                if (faceWidthRatio < FACE_VAL_CONFIG.MIN_FACE_WIDTH_RATIO) {
                    return resolve({
                        isValid: false,
                        message: FACE_VAL_CONFIG.MESSAGES.TOO_FAR,
                    });
                }

                if (!detectedFace.keypoints || detectedFace.keypoints.length < FACE_VAL_CONFIG.MIN_KEYPOINTS_COUNT) {
                    return resolve({
                        isValid: false,
                        message: FACE_VAL_CONFIG.MESSAGES.FACE_OBSTRUCTED,
                    });
                }

                // 5. Extract Keypoints (Normalized 0.0 to 1.0 Decimals)
                const keypoints = detectedFace.keypoints.map((kp: any) => ({
                    x: Number((kp.x > 1 ? kp.x / imgWidth : kp.x).toFixed(4)),
                    y: Number((kp.y > 1 ? kp.y / imgHeight : kp.y).toFixed(4)),
                }));

                return resolve({ 
                    isValid: true,
                    embedding: keypoints 
                });
            } catch (error) {
                console.error('MediaPipe validation error:', error);
                URL.revokeObjectURL(img.src);
                return resolve({
                    isValid: false,
                    message: FACE_VAL_CONFIG.MESSAGES.GENERAL_ERROR,
                });
            }
        };

        img.onerror = () => {
            URL.revokeObjectURL(img.src);
            resolve({ isValid: false, message: FACE_VAL_CONFIG.MESSAGES.INVALID_FILE });
        };
    });
}