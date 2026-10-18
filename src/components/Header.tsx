import React from 'react';
import { 
  Search, 
  Bell, 
  Settings, 
  PlusCircle, 
  Sparkles, 
  MessageSquare,
  FlaskConical,
  BookOpen
} from 'lucide-react';
import { User, AppSettings, NotificationItem } from '../types';

interface HeaderProps {
  currentUser: User;
  settings: AppSettings;
  notifications: NotificationItem[];
  onOpenSearch: () => void;
  onOpenNotifications: () => void;
  onOpenAdmin: () => void;
  onOpenNewTopic: () => void;
  activeView: 'forum' | 'prototype' | 'phoenix';
  onChangeView: (view: 'forum' | 'prototype' | 'phoenix') => void;
  onNavigateHome: () => void;
}

export const Header: React.FC<HeaderProps> = ({
  currentUser,
  settings,
  notifications,
  onOpenSearch,
  onOpenNotifications,
  onOpenAdmin,
  onOpenNewTopic,
  activeView,
  onChangeView,
  onNavigateHome,
}) => {
  const unreadCount = notifications.filter(n => !n.readAt).length;

  return (
    <header className="sticky top-0 z-30 bg-white/90 dark:bg-stone-900/90 backdrop-blur-md border-b border-stone-200 dark:border-stone-800 transition-colors">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between gap-4">
        {/* Left: Brand & Home */}
        <div className="flex items-center gap-6">
          <button 
            onClick={onNavigateHome}
            className="flex items-center gap-2.5 text-left group focus:outline-none"
          >
            <div className="w-9 h-9 rounded-xl bg-gradient-to-tr from-orange-600 to-amber-500 flex items-center justify-center text-white shadow-sm shadow-orange-500/20 group-hover:scale-105 transition-transform">
              <svg className="w-5 h-5 fill-current" viewBox="0 0 71 48">
                <path d="m26.371 33.477-.552-.1c-3.92-.729-6.397-3.1-7.57-6.829-.733-2.324.597-4.035 3.035-4.148 1.995-.092 3.362 1.055 4.57 2.39 1.557 1.72 2.984 3.558 4.514 5.305 2.202 2.515 4.797 4.134 8.347 3.634 3.183-.448 5.958-1.725 8.371-3.828.363-.316.761-.592 1.144-.886l-.241-.284c-2.027.63-4.093.841-6.205.735-3.195-.16-6.24-.828-8.964-2.582-2.486-1.601-4.319-3.746-5.19-6.611-.704-2.315.736-3.934 3.135-3.6.948.133 1.746.56 2.463 1.165.583.493 1.143 1.015 1.738 1.493 2.8 2.25 6.712 2.375 10.265-.068-5.842-.026-9.817-3.24-13.308-7.313-1.366-1.594-2.7-3.216-4.095-4.785-2.698-3.036-5.692-5.71-9.79-6.623C12.8-.623 7.745.14 2.893 2.361 1.926 2.804.997 3.319 0 4.149c.494 0 .763.006 1.032 0 2.446-.064 4.28 1.023 5.602 3.024.962 1.457 1.415 3.104 1.761 4.798.513 2.515.247 5.078.544 7.605.761 6.494 4.08 11.026 10.26 13.346 2.267.852 4.591 1.135 7.172.555Z" />
              </svg>
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="font-bold text-base tracking-tight text-stone-900 dark:text-stone-50 font-serif">
                  Idejo
                </span>
                <span className="px-1.5 py-0.5 text-[10px] font-semibold bg-orange-100 text-orange-700 dark:bg-orange-950/60 dark:text-orange-300 rounded border border-orange-200 dark:border-orange-900">
                  v0.1 PR#4
                </span>
              </div>
              <span className="text-xs text-stone-500 dark:text-stone-400 block -mt-0.5 truncate max-w-[180px] sm:max-w-[240px]">
                {settings.serverName}
              </span>
            </div>
          </button>

          {/* View switcher tabs */}
          <nav className="hidden md:flex items-center p-1 bg-stone-100 dark:bg-stone-800 rounded-lg text-xs font-medium">
            <button
              onClick={() => onChangeView('forum')}
              className={`px-3 py-1.5 rounded-md transition-all flex items-center gap-1.5 ${
                activeView === 'forum'
                  ? 'bg-white dark:bg-stone-900 text-stone-900 dark:text-stone-50 shadow-xs font-semibold'
                  : 'text-stone-600 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-200'
              }`}
            >
              <MessageSquare className="w-3.5 h-3.5 text-orange-500" />
              <span>Community Forum</span>
            </button>

            <button
              onClick={() => onChangeView('prototype')}
              className={`px-3 py-1.5 rounded-md transition-all flex items-center gap-1.5 ${
                activeView === 'prototype'
                  ? 'bg-white dark:bg-stone-900 text-stone-900 dark:text-stone-50 shadow-xs font-semibold'
                  : 'text-stone-600 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-200'
              }`}
            >
              <FlaskConical className="w-3.5 h-3.5 text-orange-500" />
              <span>Composer Prototype</span>
            </button>

            <button
              onClick={() => onChangeView('phoenix')}
              className={`px-3 py-1.5 rounded-md transition-all flex items-center gap-1.5 ${
                activeView === 'phoenix'
                  ? 'bg-white dark:bg-stone-900 text-stone-900 dark:text-stone-50 shadow-xs font-semibold'
                  : 'text-stone-600 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-200'
              }`}
            >
              <BookOpen className="w-3.5 h-3.5 text-amber-500" />
              <span>Foundations</span>
            </button>
          </nav>
        </div>

        {/* Center / Search bar trigger */}
        <div className="flex-1 max-w-md hidden sm:block">
          <button
            onClick={onOpenSearch}
            className="w-full flex items-center justify-between px-3.5 py-1.5 rounded-xl border border-stone-200 dark:border-stone-800 bg-stone-50 dark:bg-stone-950/50 text-stone-500 dark:text-stone-400 hover:border-orange-300 dark:hover:border-stone-700 hover:bg-stone-100/60 dark:hover:bg-stone-900 transition-all text-sm group"
          >
            <div className="flex items-center gap-2">
              <Search className="w-4 h-4 text-stone-400 group-hover:text-orange-500 transition-colors" />
              <span>Search topics &amp; messages...</span>
            </div>
            <kbd className="hidden lg:inline-flex px-1.5 py-0.5 text-[10px] font-mono text-stone-400 dark:text-stone-500 bg-stone-200/60 dark:bg-stone-800 rounded">
              /
            </kbd>
          </button>
        </div>

        {/* Right Actions */}
        <div className="flex items-center gap-2 sm:gap-3">
          <button
            onClick={onOpenSearch}
            className="sm:hidden p-2 text-stone-600 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 rounded-lg"
            title="Search"
          >
            <Search className="w-5 h-5" />
          </button>

          <button
            onClick={onOpenNewTopic}
            className="inline-flex items-center gap-1.5 px-3.5 py-1.5 bg-orange-600 hover:bg-orange-700 active:bg-orange-800 text-white text-xs sm:text-sm font-medium rounded-lg shadow-sm shadow-orange-600/25 transition-all hover:scale-[1.02]"
          >
            <PlusCircle className="w-4 h-4" />
            <span className="hidden xs:inline">New Topic</span>
          </button>

          <button
            onClick={onOpenNotifications}
            className="relative p-2 text-stone-600 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 rounded-lg transition-colors"
            title="Notifications"
          >
            <Bell className="w-5 h-5" />
            {unreadCount > 0 && (
              <span className="absolute top-1.5 right-1.5 w-4 h-4 bg-orange-600 text-white text-[10px] font-bold rounded-full flex items-center justify-center animate-pulse">
                {unreadCount}
              </span>
            )}
          </button>

          <button
            onClick={onOpenAdmin}
            className="p-2 text-stone-600 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 rounded-lg transition-colors"
            title="Admin &amp; Server Settings"
          >
            <Settings className="w-5 h-5" />
          </button>

          <div className="flex items-center gap-2 pl-2 border-l border-stone-200 dark:border-stone-800">
            <img
              src={currentUser.avatar}
              alt={currentUser.displayName}
              className="w-8 h-8 rounded-full object-cover ring-2 ring-orange-500/20"
            />
            <div className="hidden xl:block text-left">
              <span className="text-xs font-medium text-stone-900 dark:text-stone-100 block leading-tight">
                {currentUser.displayName}
              </span>
              <span className="text-[10px] text-orange-600 dark:text-orange-400 uppercase tracking-wider font-semibold">
                {currentUser.role}
              </span>
            </div>
          </div>
        </div>
      </div>
    </header>
  );
};
