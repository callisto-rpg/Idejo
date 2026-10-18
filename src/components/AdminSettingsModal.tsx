import React, { useState } from 'react';
import { 
  Settings, 
  X, 
  Clock, 
  Shield, 
  FolderPlus, 
  Layers, 
  UserCheck, 
  Check, 
  History, 
  AlertTriangle
} from 'lucide-react';
import { AppSettings, Category, ModAction, User } from '../types';

interface AdminSettingsModalProps {
  settings: AppSettings;
  categories: Category[];
  modActions: ModAction[];
  currentUser: User;
  onClose: () => void;
  onUpdateSettings: (newSettings: Partial<AppSettings>) => void;
  onCreateCategory: (cat: Omit<Category, 'id' | 'uri'>) => void;
}

export const AdminSettingsModal: React.FC<AdminSettingsModalProps> = ({
  settings,
  categories,
  modActions,
  currentUser,
  onClose,
  onUpdateSettings,
  onCreateCategory,
}) => {
  const [activeTab, setActiveTab] = useState<'settings' | 'categories' | 'roles' | 'audit'>('settings');

  // Form states
  const [serverName, setServerName] = useState(settings.serverName);
  const [windowSeconds, setWindowSeconds] = useState(settings.gmWindowSeconds);
  const [regMode, setRegMode] = useState(settings.registrationMode);
  const [savedSuccess, setSavedSuccess] = useState(false);

  // New category form
  const [newCatName, setNewCatName] = useState('');
  const [newCatDesc, setNewCatDesc] = useState('');
  const [newCatColor, setNewCatColor] = useState('#f97316');

  const handleSaveSettings = (e: React.FormEvent) => {
    e.preventDefault();
    onUpdateSettings({
      serverName,
      gmWindowSeconds: Number(windowSeconds),
      registrationMode: regMode,
    });
    setSavedSuccess(true);
    setTimeout(() => setSavedSuccess(false), 2000);
  };

  const handleCreateCategory = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newCatName.trim()) return;

    onCreateCategory({
      name: newCatName.trim(),
      slug: newCatName.toLowerCase().replace(/\s+/g, '-'),
      description: newCatDesc.trim() || 'Community category',
      position: categories.length + 1,
      visibility: 'public',
      color: newCatColor,
      iconName: 'MessageSquare',
    });

    setNewCatName('');
    setNewCatDesc('');
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-xs flex items-center justify-center p-4">
      <div className="bg-white dark:bg-stone-900 rounded-3xl max-w-3xl w-full shadow-2xl border border-stone-200 dark:border-stone-800 overflow-hidden flex flex-col max-h-[90vh]">
        {/* Header */}
        <div className="p-5 border-b border-stone-200 dark:border-stone-800 flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl bg-orange-100 dark:bg-orange-950/60 text-orange-600 dark:text-orange-400 flex items-center justify-center">
              <Settings className="w-4 h-4" />
            </div>
            <div>
              <h3 className="font-bold text-base text-stone-900 dark:text-stone-50 font-serif">
                Admin &amp; Server Settings (AD-01, AD-02)
              </h3>
              <span className="text-xs text-stone-500">
                Logged in as {currentUser.displayName} ({currentUser.roleTitle || currentUser.role})
              </span>
            </div>
          </div>

          <button
            onClick={onClose}
            className="p-1.5 text-stone-400 hover:text-stone-600 dark:hover:text-stone-200 rounded-lg hover:bg-stone-100 dark:hover:bg-stone-800"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Tab Navigation */}
        <div className="px-5 border-b border-stone-200 dark:border-stone-800 flex items-center gap-4 text-xs font-semibold overflow-x-auto bg-stone-50/50 dark:bg-stone-950/30">
          <button
            onClick={() => setActiveTab('settings')}
            className={`py-3 border-b-2 transition-colors shrink-0 ${
              activeTab === 'settings'
                ? 'border-orange-600 text-orange-600 dark:text-orange-400'
                : 'border-transparent text-stone-500 hover:text-stone-900 dark:hover:text-stone-300'
            }`}
          >
            Server &amp; Window Settings
          </button>
          <button
            onClick={() => setActiveTab('categories')}
            className={`py-3 border-b-2 transition-colors shrink-0 ${
              activeTab === 'categories'
                ? 'border-orange-600 text-orange-600 dark:text-orange-400'
                : 'border-transparent text-stone-500 hover:text-stone-900 dark:hover:text-stone-300'
            }`}
          >
            Categories ({categories.length})
          </button>
          <button
            onClick={() => setActiveTab('roles')}
            className={`py-3 border-b-2 transition-colors shrink-0 ${
              activeTab === 'roles'
                ? 'border-orange-600 text-orange-600 dark:text-orange-400'
                : 'border-transparent text-stone-500 hover:text-stone-900 dark:hover:text-stone-300'
            }`}
          >
            Roles &amp; Permission Matrix
          </button>
          <button
            onClick={() => setActiveTab('audit')}
            className={`py-3 border-b-2 transition-colors shrink-0 ${
              activeTab === 'audit'
                ? 'border-orange-600 text-orange-600 dark:text-orange-400'
                : 'border-transparent text-stone-500 hover:text-stone-900 dark:hover:text-stone-300'
            }`}
          >
            Moderation Log ({modActions.length})
          </button>
        </div>

        {/* Body content */}
        <div className="p-6 overflow-y-auto flex-1 text-sm space-y-6">
          {activeTab === 'settings' && (
            <form onSubmit={handleSaveSettings} className="space-y-5 max-w-xl">
              <div>
                <label className="block text-xs font-semibold uppercase tracking-wider text-stone-500 mb-1.5">
                  Server / Community Name
                </label>
                <input
                  type="text"
                  value={serverName}
                  onChange={(e) => setServerName(e.target.value)}
                  className="w-full px-3.5 py-2.5 bg-stone-50 dark:bg-stone-800 border border-stone-200 dark:border-stone-700 rounded-xl text-sm font-medium text-stone-900 dark:text-stone-100"
                />
              </div>

              {/* GM-15 Server-Wide Growing Message Window */}
              <div className="p-4 bg-orange-50/70 dark:bg-orange-950/30 border border-orange-200 dark:border-orange-900/50 rounded-2xl space-y-2">
                <div className="flex items-center gap-2 text-orange-900 dark:text-orange-200 font-semibold text-xs uppercase tracking-wider">
                  <Clock className="w-4 h-4 text-orange-600" />
                  <span>Growing Message Window Length (GM-15, AD-04)</span>
                </div>
                <p className="text-xs text-stone-600 dark:text-stone-300">
                  Duration an open message stays active for subsequent lines. Minimum 10s, default 45s.
                </p>

                <div className="flex items-center gap-4 pt-1">
                  <input
                    type="range"
                    min={15}
                    max={120}
                    step={5}
                    value={windowSeconds}
                    onChange={(e) => setWindowSeconds(Number(e.target.value))}
                    className="flex-1 accent-orange-600 cursor-pointer"
                  />
                  <span className="font-mono font-bold text-sm text-orange-700 dark:text-orange-300 px-3 py-1 bg-white dark:bg-stone-900 rounded-lg border border-orange-200 dark:border-orange-800 shrink-0">
                    {windowSeconds} seconds
                  </span>
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold uppercase tracking-wider text-stone-500 mb-1.5">
                  Registration Mode (AC-01)
                </label>
                <select
                  value={regMode}
                  onChange={(e) => setRegMode(e.target.value as any)}
                  className="w-full px-3.5 py-2.5 bg-stone-50 dark:bg-stone-800 border border-stone-200 dark:border-stone-700 rounded-xl text-sm font-medium text-stone-900 dark:text-stone-100"
                >
                  <option value="open">Open Registration (Email verification)</option>
                  <option value="invite-only">Invite-Only (Requires valid invite code)</option>
                </select>
              </div>

              <div className="flex items-center gap-3 pt-3">
                <button
                  type="submit"
                  className="px-5 py-2.5 bg-orange-600 hover:bg-orange-700 text-white font-semibold text-xs rounded-xl shadow-sm transition-colors flex items-center gap-2"
                >
                  <Check className="w-4 h-4" />
                  <span>Save Server Configuration</span>
                </button>
                {savedSuccess && (
                  <span className="text-xs text-emerald-600 font-semibold animate-fade-in">
                    Settings successfully saved!
                  </span>
                )}
              </div>
            </form>
          )}

          {activeTab === 'categories' && (
            <div className="space-y-6">
              {/* Add category form */}
              <form onSubmit={handleCreateCategory} className="p-4 bg-stone-50 dark:bg-stone-950/60 border border-stone-200 dark:border-stone-800 rounded-2xl space-y-3">
                <h4 className="font-bold text-xs uppercase tracking-wider text-stone-600 dark:text-stone-300">
                  Create New Category (RP-03)
                </h4>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                  <input
                    type="text"
                    required
                    placeholder="Category Name"
                    value={newCatName}
                    onChange={(e) => setNewCatName(e.target.value)}
                    className="sm:col-span-1 px-3 py-2 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl text-xs"
                  />
                  <input
                    type="text"
                    placeholder="Brief description"
                    value={newCatDesc}
                    onChange={(e) => setNewCatDesc(e.target.value)}
                    className="sm:col-span-1 px-3 py-2 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl text-xs"
                  />
                  <div className="sm:col-span-1 flex items-center gap-2">
                    <input
                      type="color"
                      value={newCatColor}
                      onChange={(e) => setNewCatColor(e.target.value)}
                      className="w-9 h-8 p-0.5 rounded-lg border border-stone-300 dark:border-stone-700 cursor-pointer"
                    />
                    <button
                      type="submit"
                      disabled={!newCatName.trim()}
                      className="flex-1 px-3 py-2 bg-orange-600 hover:bg-orange-700 disabled:opacity-50 text-white font-semibold text-xs rounded-xl shadow-xs"
                    >
                      Add Category
                    </button>
                  </div>
                </div>
              </form>

              {/* Current Categories List */}
              <div className="space-y-2">
                {categories.map((c, idx) => (
                  <div
                    key={c.id}
                    className="p-3 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-800 rounded-xl flex items-center justify-between text-xs"
                  >
                    <div className="flex items-center gap-2.5">
                      <span className="font-mono text-stone-400 text-[10px]">#{idx + 1}</span>
                      <span
                        className="w-3 h-3 rounded-full"
                        style={{ backgroundColor: c.color }}
                      />
                      <div>
                        <strong className="text-stone-900 dark:text-stone-100 font-semibold">
                          {c.name}
                        </strong>
                        <p className="text-stone-400 text-[11px] truncate max-w-md">
                          {c.description}
                        </p>
                      </div>
                    </div>
                    <span className="px-2 py-0.5 rounded-full bg-stone-100 dark:bg-stone-800 text-stone-600 dark:text-stone-400 text-[10px] uppercase font-semibold">
                      {c.visibility}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {activeTab === 'roles' && (
            <div className="space-y-4">
              <div className="p-3 bg-stone-50 dark:bg-stone-950/60 rounded-xl border border-stone-200 dark:border-stone-800 text-xs text-stone-600 dark:text-stone-400">
                Per-category permissions evaluate four rights (RP-04, RP-05): <strong>View</strong>, <strong>Start topics</strong>, <strong>Post</strong>, and <strong>Moderate</strong>. An explicit deny always wins (RP-06).
              </div>

              <div className="overflow-x-auto border border-stone-200 dark:border-stone-800 rounded-2xl">
                <table className="w-full text-left text-xs">
                  <thead className="bg-stone-100/70 dark:bg-stone-800/60 text-stone-600 dark:text-stone-300 uppercase tracking-wider font-semibold border-b border-stone-200 dark:border-stone-800">
                    <tr>
                      <th className="p-3">Role</th>
                      <th className="p-3 text-center">View</th>
                      <th className="p-3 text-center">Start Topics</th>
                      <th className="p-3 text-center">Post Messages</th>
                      <th className="p-3 text-center">Moderate</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-stone-200 dark:divide-stone-800">
                    <tr>
                      <td className="p-3 font-semibold text-stone-900 dark:text-stone-100 flex items-center gap-2">
                        <span className="w-2.5 h-2.5 rounded-full bg-orange-500" />
                        Admin
                      </td>
                      <td className="p-3 text-center font-bold text-emerald-600">Allow</td>
                      <td className="p-3 text-center font-bold text-emerald-600">Allow</td>
                      <td className="p-3 text-center font-bold text-emerald-600">Allow</td>
                      <td className="p-3 text-center font-bold text-emerald-600">Allow</td>
                    </tr>
                    <tr>
                      <td className="p-3 font-semibold text-stone-900 dark:text-stone-100 flex items-center gap-2">
                        <span className="w-2.5 h-2.5 rounded-full bg-purple-500" />
                        Moderator
                      </td>
                      <td className="p-3 text-center font-bold text-emerald-600">Allow</td>
                      <td className="p-3 text-center font-bold text-emerald-600">Allow</td>
                      <td className="p-3 text-center font-bold text-emerald-600">Allow</td>
                      <td className="p-3 text-center font-bold text-emerald-600">Allow</td>
                    </tr>
                    <tr>
                      <td className="p-3 font-semibold text-stone-900 dark:text-stone-100 flex items-center gap-2">
                        <span className="w-2.5 h-2.5 rounded-full bg-sky-500" />
                        Member
                      </td>
                      <td className="p-3 text-center font-bold text-emerald-600">Allow</td>
                      <td className="p-3 text-center font-bold text-emerald-600">Allow</td>
                      <td className="p-3 text-center font-bold text-emerald-600">Allow</td>
                      <td className="p-3 text-center text-stone-400">Deny</td>
                    </tr>
                    <tr>
                      <td className="p-3 font-semibold text-stone-900 dark:text-stone-100 flex items-center gap-2">
                        <span className="w-2.5 h-2.5 rounded-full bg-stone-400" />
                        Guest
                      </td>
                      <td className="p-3 text-center font-bold text-emerald-600">Allow</td>
                      <td className="p-3 text-center text-stone-400">Deny</td>
                      <td className="p-3 text-center text-stone-400">Deny</td>
                      <td className="p-3 text-center text-stone-400">Deny</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {activeTab === 'audit' && (
            <div className="space-y-3">
              <h4 className="font-bold text-xs uppercase tracking-wider text-stone-600 dark:text-stone-300">
                Action Log (MO-03, SP-06)
              </h4>
              {modActions.map((action) => (
                <div
                  key={action.id}
                  className="p-3 bg-stone-50 dark:bg-stone-950/60 border border-stone-200 dark:border-stone-800 rounded-xl flex items-center justify-between text-xs"
                >
                  <div>
                    <div className="flex items-center gap-2 font-medium text-stone-800 dark:text-stone-200">
                      <span className="text-orange-600 dark:text-orange-400">
                        {action.moderator.displayName}
                      </span>
                      <span>performed <strong>{action.action}</strong> on {action.targetDescription}</span>
                    </div>
                    <span className="text-[11px] text-stone-400 italic">
                      Reason: "{action.reason}"
                    </span>
                  </div>
                  <span className="text-[10px] text-stone-400 shrink-0">
                    {action.createdAt}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
