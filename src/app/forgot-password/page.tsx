"use client";
import { useState } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import axios from "axios";

export default function ForgotPasswordPage() {
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const searchParams = useSearchParams();
  const router = useRouter();

  const token = searchParams.get("t");

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setMessage("");

    if (!token) return setMessage("Invalid or missing reset token.");
    if (password !== confirmPassword) return setMessage("Passwords do not match.");
    if (password.length < 8) return setMessage("Password must be at least 8 characters long.");

    try {
      setLoading(true);
      await axios.post("http://192.168.18.165:3000/api/auth/reset-password", {
        token,
        newPassword: password,
      });
      setMessage("✅ Password reset successful! Redirecting to login...");
      setTimeout(() => router.push("/login"), 2000);
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
          <input
            type="password"
            placeholder="New Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="w-full border border-gray-300 rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-blue-400"
            required
          />
          <input
            type="password"
            placeholder="Confirm New Password"
            value={confirmPassword}
            onChange={(e) => setConfirmPassword(e.target.value)}
            className="w-full border border-gray-300 rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-blue-400"
            required
          />
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
