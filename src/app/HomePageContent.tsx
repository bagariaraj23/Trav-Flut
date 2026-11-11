"use client";

import { useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";

export default function HomePageContent() {
    const searchParams = useSearchParams();
    const [error, setError] = useState<string | null>(null);
    const [message, setMessage] = useState<string | null>(null);

    useEffect(() => {
        const errorParam = searchParams.get("error");
        const messageParam = searchParams.get("message");

        if (errorParam) setError(errorParam);
        if (messageParam) setMessage(messageParam);
    }, [searchParams]);

    return (
        <div className="flex min-h-screen items-center justify-center bg-gray-100">
            <div className="w-full max-w-md bg-white shadow-lg rounded-2xl p-8 text-center">
                <div className="mb-6">
                    <img
                        src="/tripthread-logo.svg"
                        alt="TripThread"
                        className="mx-auto h-12"
                    />
                </div>

                <h1 className="text-2xl font-semibold text-gray-800 mb-4">
                    Welcome to TripThread
                </h1>

                {error && (
                    <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg">
                        <div className="text-red-600 font-medium mb-2">
                            {error === "invalid-reset-link" && "Invalid Reset Link"}
                            {error === "expired-reset-link" && "Expired Reset Link"}
                            {error === "already-used" && "Link Already Used"}
                        </div>
                        <p className="text-red-700 text-sm">
                            {message || "An error occurred with your password reset link."}
                        </p>
                    </div>
                )}

                <p className="text-gray-600 mb-6">
                    Welcome to TripThread - Your travel companion for sharing amazing journeys.
                </p>

                <div className="space-y-3">
                    <button
                        onClick={() => (window.location.href = "/login")}
                        className="w-full bg-blue-600 text-white rounded-lg py-2 hover:bg-blue-700 transition"
                    >
                        Login
                    </button>
                    <button
                        onClick={() => (window.location.href = "/signup")}
                        className="w-full bg-gray-600 text-white rounded-lg py-2 hover:bg-gray-700 transition"
                    >
                        Sign Up
                    </button>
                </div>

                <div className="mt-6 text-sm text-gray-500">
                    <p>
                        Forgot your password?{" "}
                        <button
                            onClick={() => (window.location.href = "/forgot-password")}
                            className="text-blue-600 hover:text-blue-700 underline"
                        >
                            Reset it here
                        </button>
                    </p>
                </div>
            </div>
        </div>
    );
}
