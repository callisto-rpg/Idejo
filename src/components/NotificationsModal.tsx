import React from 'react';
import { Bell, X, Check, MessageSquare, AtSign, ArrowRight } from 'lucide-react';
import { NotificationItem, Topic } from '../types';

interface NotificationsModalProps {
  notifications: NotificationItem[];
  topics: Topic[];
  onClose: () => void;
  onSelectTopic: (topic: Topic) => void;
  onMarkAllAsRead: () => void;
}

export const NotificationsModal: React.FC<NotificationsModalProps> = ({
  notifications,
  topics,
  onClose,
  onSelectTopic,
  onMarkAllAsRead,
}) => {
  return (
    <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-xs flex items-start justify-center p-4 pt-16 sm:pt-24">
      <div className="bg-white dark:bg-stone-900 rounded-3xl max-w-lg w-full shadow-2xl border border-stone-200 dark:border-stone-800 overflow-hidden flex flex-col max-h-[80vh]">
        {/* Header */}
        <div className="p-4 border-b border-stone-200 dark:border-stone-800 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Bell className="w-5 h-5 text-orange-500" />
            <h3 className="font-bold text-base text-stone-900 dark:text-stone-100 font-serif">
              Notifications (NO-01, NO-02)
            </h3>
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={onMarkAllAsRead}
              className="text-xs text-orange-600 dark:text-orange-400 hover:underline font-medium"
            >
              Mark all read
            </button>
            <button
              onClick={onClose}
              className="p-1 text-stone-400 hover:text-stone-600 rounded"
            >
              <X className="w-4 h-4" />
            </button>
          </div>
        </div>

        {/* List */}
        <div className="p-4 space-y-2 overflow-y-auto flex-1">
          {notifications.length === 0 ? (
            <div className="py-8 text-center text-xs text-stone-500">
              No notifications yet. You will be notified when someone @mentions you or replies to your growing messages.
            </div>
          ) : (
            notifications.map((notif) => {
              const topic = topics.find((t) => t.id === notif.topicId);
              const isUnread = !notif.readAt;

              return (
                <div
                  key={notif.id}
                  onClick={() => {
                    if (topic) {
                      onSelectTopic(topic);
                      onClose();
                    }
                  }}
                  className={`p-3.5 rounded-2xl border transition-all cursor-pointer flex items-start gap-3 ${
                    isUnread
                      ? 'bg-orange-50/60 dark:bg-orange-950/20 border-orange-200 dark:border-orange-900/60'
                      : 'bg-white dark:bg-stone-900 border-stone-200/80 dark:border-stone-800 hover:border-stone-300'
                  }`}
                >
                  <div
                    className={`p-2 rounded-xl shrink-0 ${
                      notif.kind === 'mention'
                        ? 'bg-amber-100 text-amber-700 dark:bg-amber-950/60 dark:text-amber-300'
                        : 'bg-orange-100 text-orange-700 dark:bg-orange-950/60 dark:text-orange-300'
                    }`}
                  >
                    {notif.kind === 'mention' ? (
                      <AtSign className="w-4 h-4" />
                    ) : (
                      <MessageSquare className="w-4 h-4" />
                    )}
                  </div>

                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between text-xs text-stone-500 mb-0.5">
                      <span className="font-semibold text-stone-800 dark:text-stone-200">
                        {notif.actor.displayName}
                      </span>
                      <span>{notif.createdAt}</span>
                    </div>

                    <p className="text-xs text-stone-700 dark:text-stone-300 font-medium line-clamp-2">
                      {notif.snippet}
                    </p>

                    <span className="text-[11px] text-orange-600 dark:text-orange-400 mt-1 block truncate">
                      in {notif.topicTitle} &rarr;
                    </span>
                  </div>

                  {isUnread && (
                    <span className="w-2 h-2 rounded-full bg-orange-600 shrink-0 mt-1.5" />
                  )}
                </div>
              );
            })
          )}
        </div>
      </div>
    </div>
  );
};
