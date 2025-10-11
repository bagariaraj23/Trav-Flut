"use client";

import { useRouter } from "next/navigation";

export default function ResetSuccessPage() {
  const router = useRouter();

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-100">
      <div className="w-full max-w-md bg-white shadow-lg rounded-2xl p-8 text-center">
        <div className="mb-6 text-green-500">
          <svg
            className="mx-auto h-16 w-16"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
            xmlns="http://www.w3.org/2000/svg"
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
        <p className="text-gray-600">
          Your password has been successfully reset. You can now log in with your new credentials.
        </p>
      </div>
    </div>
  );
}
