"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import axios from "axios";

export default function ResetSuccessContent() {
    const router = useRouter();
    const searchParams = useSearchParams();
    const [validating, setValidating] = useState(true);
    const [validationError, setValidationError] = useState("");

    const token = searchParams.get("t");
    const email = searchParams.get("email");

    useEffect(() => {
        validateToken();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    const validateToken = async () => {
        if (!token || !email) {
            setValidationError("Invalid or missing reset token.");
            setValidating(false);
            return;
        }

        try {
            const apiBaseUrl =
                process.env.NEXT_PUBLIC_API_BASE_URL || "http://localhost:3000/api";
            const response = await axios.post(
                `${apiBaseUrl}/auth/validate-reset-token`,
                { token, email, allowUsed: true },
                { headers: { "Content-Type": "application/json" } }
            );

            if (!response.data.valid) {
                setValidationError(response.data.message || "Invalid reset token.");
                setValidating(false);
                return;
            }

            setValidating(false);
        } catch (error: any) {
            const errorMessage =
                error.response?.data?.message || "Failed to validate reset token.";
            setValidationError(errorMessage);
            setValidating(false);
        }
    };

    if (validating) {
        return (
            <div className="flex min-h-screen items-center justify-center bg-gray-100">
                <div className="w-full max-w-md bg-white shadow-lg rounded-2xl p-8 text-center">
                    <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto mb-4"></div>
                    <p className="text-gray-600">Validating reset token...</p>
                </div>
            </div>
        );
    }

    if (validationError) {
        return (
            <div className="flex min-h-screen items-center justify-center bg-gray-100">
                <div className="w-full max-w-md bg-white shadow-lg rounded-2xl p-8 text-center">
                    <div className="mb-6 text-red-500">
                        <svg
                            className="mx-auto h-16 w-16"
                            fill="none"
                            stroke="currentColor"
                            viewBox="0 0 24 24"
                        >
                            <path
                                strokeLinecap="round"
                                strokeLinejoin="round"
                                strokeWidth={2}
                                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"
                            />
                        </svg>
                    </div>
                    <h1 className="text-2xl font-semibold text-gray-800 mb-4">
                        Invalid Reset Link
                    </h1>
                    <p className="text-gray-600 mb-6">{validationError}</p>
                    <button
                        onClick={() => router.push("/")}
                        className="w-full bg-blue-600 text-white rounded-lg py-2 hover:bg-blue-700 transition"
                    >
                        Go to Home
                    </button>
                </div>
            </div>
        );
    }

    return (
        <div className="flex min-h-screen items-center justify-center bg-gray-100">
            <div className="w-full max-w-md bg-white shadow-lg rounded-2xl p-8 text-center">
                <div className="mb-6 text-green-500">
                    <svg
                        className="mx-auto h-16 w-16"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                    >
                        <path
                            strokeLinecap="round"
                            strokeLinejoin="round"
                            strokeWidth={2}
                            d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                        />
                    </svg>
                </div>
                <h1 className="text-2xl font-semibold text-gray-800 mb-4">
                    Password Reset Successful!
                </h1>
                <p className="text-gray-600 mb-6">
                    Your password has been successfully reset. You can now log in with your new credentials.
                </p>
            </div>
        </div>
    );
}
