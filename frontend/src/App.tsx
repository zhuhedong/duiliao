import { Navigate, Route, Routes } from "react-router-dom";
import { ProtectedRoute } from "./auth/ProtectedRoute";
import { AppLayout } from "./components/AppLayout";
import { LoginPage } from "./pages/LoginPage";
import { BootstrapPage } from "./pages/BootstrapPage";
import { DashboardPage } from "./pages/DashboardPage";
import { ProfilePage } from "./pages/ProfilePage";
import { CollectorSourcesPage } from "./pages/collector/SourcesPage";
import { CollectorDrawsPage } from "./pages/collector/DrawsPage";
import { CollectorConsensusPage } from "./pages/collector/ConsensusPage";
import { CollectorRatingsPage } from "./pages/collector/RatingsPage";
import { CollectorMonitorPage } from "./pages/collector/MonitorPage";
import { CollectorFetchPlatformPage } from "./pages/collector/FetchPlatformPage";
import { CollectorNumbersPage } from "./pages/collector/NumbersPage";
import { CollectorAIAnalysisPage } from "./pages/collector/AIAnalysisPage";
import { TrendPage } from "./pages/collector/TrendPage";
import { PingteRankingPage } from "./pages/collector/PingteRankingPage";
import { RecordsPage } from "./pages/records/RecordsPage";
import { SystemSettingsPage } from "./pages/SystemSettingsPage";

export function App() {
  return (
    <Routes>
      {/* Public auth routes */}
      <Route path="/login" element={<LoginPage />} />
      <Route path="/register" element={<Navigate to="/login" replace />} />
      <Route path="/bootstrap" element={<BootstrapPage />} />

      {/* Everything below requires a logged-in session */}
      <Route
        element={
          <ProtectedRoute>
            <AppLayout />
          </ProtectedRoute>
        }
      >
        <Route path="/" element={<DashboardPage />} />
        <Route path="/records" element={<RecordsPage />} />
        <Route path="/collector/sources" element={<CollectorSourcesPage />} />
        <Route path="/collector/draws" element={<CollectorDrawsPage />} />
        <Route path="/collector/trend" element={<TrendPage />} />
        <Route path="/trend" element={<TrendPage />} />
        <Route path="/collector/pingte-ranking" element={<PingteRankingPage />} />
        <Route path="/pingte-ranking" element={<PingteRankingPage />} />
        <Route path="/collector/consensus" element={<CollectorConsensusPage />} />
        <Route path="/collector/ai-analysis" element={<CollectorAIAnalysisPage />} />
        <Route path="/collector/ratings" element={<CollectorRatingsPage />} />
        <Route path="/collector/monitor" element={<CollectorMonitorPage />} />
        <Route path="/collector/platform" element={<CollectorFetchPlatformPage />} />
        <Route path="/collector/numbers" element={<CollectorNumbersPage />} />
        <Route path="/profile" element={<ProfilePage />} />
        <Route path="/settings" element={<SystemSettingsPage />} />
      </Route>



      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
