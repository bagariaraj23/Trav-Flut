"use client";
import { useState, Suspense } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import axios from "axios";

export default function ForgotPasswordPageWrapper() {
  return (
    <Suspense>
      <ForgotPasswordPage />
    </Suspense>
  );
}

function ForgotPasswordPage() {
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showCurrent, setShowCurrent] = useState(false);
  const [showNew, setShowNew] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const searchParams = useSearchParams();
  const router = useRouter();

  const token = searchParams.get("t");

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setMessage("");

    if (!token) return setMessage("Invalid or missing reset token.");
    if (newPassword !== confirmPassword) return setMessage("New passwords do not match.");
    if (newPassword.length < 8) return setMessage("New password must be at least 8 characters long.");
    if (!currentPassword) return setMessage("Current password is required.");

    // Show confirmation dialog
    const confirmed = window.confirm(
      "Are you sure you want to reset your password? You will need to use the new password to login and will be logged out of all devices."
    );

    try {
      if (!confirmed) {
        return;
      }
      setLoading(true);

      // Use environment variable for API URL
      const apiBaseUrl = process.env.NEXT_PUBLIC_API_BASE_URL || 'http://localhost:3000/api';

      await axios.post(
        `${apiBaseUrl}/auth/reset-password`,
        { token, currentPassword, newPassword },
        { headers: { "Content-Type": "application/json" } }
      );
      router.replace("/reset-success");
    } catch (err: any) {
      setMessage(
        err.response?.data?.message || "❌ Failed to reset password. Try again."
      );
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-100">
      <div className="w-full max-w-md bg-white shadow-lg rounded-2xl p-8">
        <h1 className="text-2xl font-semibold text-gray-800 mb-6 text-center">
          Reset Your Password
        </h1>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="relative">
            <input
              type={showCurrent ? "text" : "password"}
              placeholder="Current Password"
              value={currentPassword}
              onChange={(e) => setCurrentPassword(e.target.value)}
              className="w-full border border-gray-300 rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-blue-400"
              required
            />
            <button type="button" aria-label="Toggle current password visibility" onClick={() => setShowCurrent((v) => !v)} className="absolute inset-y-0 right-3 my-auto text-sm text-gray-500">
              {showCurrent ? "Hide" : "Show"}
            </button>
          </div>
          <div className="relative">
            <input
              type={showNew ? "text" : "password"}
              placeholder="New Password"
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              className="w-full border border-gray-300 rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-blue-400"
              required
            />
            <button type="button" aria-label="Toggle new password visibility" onClick={() => setShowNew((v) => !v)} className="absolute inset-y-0 right-3 my-auto text-sm text-gray-500">
              {showNew ? "Hide" : "Show"}
            </button>
          </div>
          <div className="relative">
            <input
              type={showConfirm ? "text" : "password"}
              placeholder="Confirm New Password"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              className="w-full border border-gray-300 rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-blue-400"
              required
            />
            <button type="button" aria-label="Toggle confirm password visibility" onClick={() => setShowConfirm((v) => !v)} className="absolute inset-y-0 right-3 my-auto text-sm text-gray-500">
              {showConfirm ? "Hide" : "Show"}
            </button>
          </div>
          <button
            type="submit"
            disabled={loading}
            className="w-full bg-blue-600 text-white rounded-lg py-2 hover:bg-blue-700 transition disabled:opacity-50"
          >
            {loading ? "Updating..." : "Reset Password"}
          </button>
        </form>
        {message && (
          <p className="text-center text-sm text-gray-700 mt-4">{message}</p>
        )}
      </div>
    </div>
  );
}
