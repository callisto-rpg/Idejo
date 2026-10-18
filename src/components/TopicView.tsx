import React, { useState } from 'react';
import { 
  ArrowLeft, 
  Pin, 
  Lock, 
  Unlock, 
  FolderInput, 
  Bookmark, 
  GitFork, 
  Check, 
  MessageSquare,
  Sparkles,
  Info
} from 'lucide-react';
import { Topic, Category, Message, User } from '../types';
import { MessageItem } from './MessageItem';
import { GrowingMessageComposer } from './GrowingMessageComposer';

interface TopicViewProps {
  topic: Topic;
  category: Category;
  categories: Category[];
  messages: Message[];
  currentUser: User;
  onBack: () => void;
  onCommitChanges: (text: string) => void;
  onStartNewMessage: (text: string, closed?: boolean) => void;
  onCloseOpenMessageAndStartNew?: (text: string) => void;
  onCloseOpenMessage: () => void;
  onToggleLock: (topicId: string) => void;
  onTogglePin: (topicId: string) => void;
  onMoveCategory: (topicId: string, newCategoryId: string) => void;
  onDeleteMessage?: (messageId: string) => void;
  onForceCloseMessage?: (messageId: string) => void;
  onForkToNewTopic: (sourceMessage: Message, sourceTopic: Topic) => void;
  windowDurationSeconds: number;
}

export const TopicView: React.FC<TopicViewProps> = ({
  topic,
  category,
  categories,
  messages,
  currentUser,
  onBack,
  onCommitChanges,
  onStartNewMessage,
  onCloseOpenMessageAndStartNew,
  onCloseOpenMessage,
  onToggleLock,
  onTogglePin,
  onMoveCategory,
  onDeleteMessage,
  onForceCloseMessage,
  onForkToNewTopic,
  windowDurationSeconds,
}) => {
  const [following, setFollowing] = useState(false);
  const [replyTarget, setReplyTarget] = useState<Message | null>(null);
  const [showMoveModal, setShowMoveModal] = useState(false);

  const isModOrAdmin = currentUser.role === 'admin' || currentUser.role === 'moderator';

  // Find active open message belonging to the current user in this topic
  const activeOpenMessage = messages.find(
    (m) => m.topicId === topic.id && m.state === 'open' && m.author.id === currentUser.id
  ) || null;

  // Determine whether replies have arrived after the author's open message
  const activeOpenIndex = activeOpenMessage
    ? messages.findIndex((m) => m.id === activeOpenMessage.id)
    : -1;
  const hasRepliesBelow = activeOpenIndex >= 0 && activeOpenIndex < messages.length - 1;

  // Trigger to move focus to the bottom empty text entry box on Ctrl+Enter
  const [bottomFocusTrigger, setBottomFocusTrigger] = useState(0);
  const [bottomComposerKey, setBottomComposerKey] = useState(0);

  const handleCtrlEnter = () => {
    onCloseOpenMessage();
    setBottomComposerKey((k) => k + 1);
    setBottomFocusTrigger((t) => t + 1);
  };

  return (
    <div className="max-w-4xl mx-auto px-4 sm:px-6 py-6 space-y-6">
      {/* Top Bar: Navigation & Topic Controls */}
      <div className="flex flex-wrap items-center justify-between gap-3 pb-4 border-b border-stone-200 dark:border-stone-800">
        <button
          onClick={onBack}
          className="inline-flex items-center gap-1.5 text-xs sm:text-sm font-medium text-stone-600 dark:text-stone-400 hover:text-orange-600 dark:hover:text-orange-400 transition-colors"
        >
          <ArrowLeft className="w-4 h-4" />
          <span>Back to {category.name}</span>
        </button>

        <div className="flex items-center gap-2">
          {/* Follow topic button (TP-13) */}
          <button
            onClick={() => setFollowing(!following)}
            className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium border transition-colors ${
              following
                ? 'bg-orange-50 border-orange-300 text-orange-700 dark:bg-orange-950/60 dark:border-orange-800 dark:text-orange-300'
                : 'bg-white dark:bg-stone-900 border-stone-200 dark:border-stone-800 text-stone-700 dark:text-stone-300 hover:bg-stone-50'
            }`}
          >
            <Bookmark className={`w-3.5 h-3.5 ${following ? 'fill-current' : ''}`} />
            <span>{following ? 'Following (TP-13)' : 'Follow Topic'}</span>
          </button>

          {/* Moderator Tools (MO-02) */}
          {isModOrAdmin && (
            <div className="flex items-center gap-1.5 pl-2 border-l border-stone-200 dark:border-stone-800">
              <button
                onClick={() => onTogglePin(topic.id)}
                className={`p-1.5 rounded-lg border transition-colors ${
                  topic.pinned
                    ? 'bg-amber-100 border-amber-300 text-amber-800 dark:bg-amber-950 dark:border-amber-800 dark:text-amber-200'
                    : 'bg-white dark:bg-stone-900 border-stone-200 dark:border-stone-800 text-stone-600 dark:text-stone-400 hover:bg-stone-50'
                }`}
                title={topic.pinned ? 'Unpin topic' : 'Pin topic to top (TP-14)'}
              >
                <Pin className="w-4 h-4" />
              </button>

              <button
                onClick={() => onToggleLock(topic.id)}
                className={`p-1.5 rounded-lg border transition-colors ${
                  topic.state === 'locked'
                    ? 'bg-red-100 border-red-300 text-red-800 dark:bg-red-950 dark:border-red-800 dark:text-red-200'
                    : 'bg-white dark:bg-stone-900 border-stone-200 dark:border-stone-800 text-stone-600 dark:text-stone-400 hover:bg-stone-50'
                }`}
                title={topic.state === 'locked' ? 'Unlock topic' : 'Lock topic (TP-14)'}
              >
                {topic.state === 'locked' ? <Lock className="w-4 h-4" /> : <Unlock className="w-4 h-4" />}
              </button>

              <button
                onClick={() => setShowMoveModal(true)}
                className="p-1.5 rounded-lg border bg-white dark:bg-stone-900 border-stone-200 dark:border-stone-800 text-stone-600 dark:text-stone-400 hover:bg-stone-50"
                title="Move topic to another category (TP-15)"
              >
                <FolderInput className="w-4 h-4" />
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Forked origin backlink banner (TP-09) */}
      {topic.forkedFromMessageId && (
        <div className="p-3 bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-900/60 rounded-xl flex items-center gap-2 text-xs text-amber-800 dark:text-amber-200">
          <GitFork className="w-4 h-4 text-amber-600 shrink-0" />
          <span>
            This topic was forked from message{' '}
            <code className="px-1 py-0.5 bg-amber-100 dark:bg-amber-900 rounded font-mono">
              #{topic.forkedFromMessageId}
            </code>
            {topic.forkedFromTopicTitle ? ` in "${topic.forkedFromTopicTitle}"` : ''}.
          </span>
        </div>
      )}

      {/* Topic Header Information */}
      <div className="space-y-2">
        <div className="flex flex-wrap items-center gap-2">
          <span
            className="px-2.5 py-0.5 rounded-full text-xs font-semibold"
            style={{
              backgroundColor: `${category.color}15`,
              color: category.color,
            }}
          >
            {category.name}
          </span>

          {topic.pinned && (
            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-semibold bg-amber-100 text-amber-800 dark:bg-amber-950/60 dark:text-amber-300">
              <Pin className="w-3 h-3" />
              Pinned
            </span>
          )}

          {topic.state === 'locked' && (
            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-semibold bg-red-100 text-red-800 dark:bg-red-950/60 dark:text-red-300">
              <Lock className="w-3 h-3" />
              Locked
            </span>
          )}
        </div>

        <h1 className="text-xl sm:text-2xl font-bold tracking-tight text-stone-900 dark:text-stone-50 font-serif">
          {topic.title}
        </h1>

        <div className="flex items-center gap-2 text-xs text-stone-500">
          <span>Started by <strong className="font-medium text-stone-700 dark:text-stone-300">{topic.author.displayName}</strong></span>
          <span>&bull;</span>
          <span>{topic.messageCount} messages</span>
          <span>&bull;</span>
          <span>Active {topic.lastActivityAt}</span>
        </div>
      </div>

      {/* Messages Stream List */}
      <div className="space-y-4 pt-2">
        {messages.map((message) => {
          // If this is the active open message belonging to the current user
          if (activeOpenMessage && message.id === activeOpenMessage.id) {
            // When replies have arrived below it, the message being typed in moves up here (GM-08)
            if (hasRepliesBelow) {
              return (
                <div key={`in_place_${message.id}`} className="space-y-1.5">
                  <div className="flex items-center gap-2.5">
                    <img
                      src={currentUser.avatar}
                      alt={currentUser.displayName}
                      className="w-7 h-7 rounded-full object-cover ring-1 ring-stone-200 dark:ring-stone-800"
                    />
                    <span className="font-semibold text-sm text-stone-900 dark:text-stone-100">
                      {currentUser.displayName}
                    </span>
                    <span className="text-xs text-stone-400">
                      {currentUser.roleTitle || currentUser.role}
                    </span>
                  </div>
                  <GrowingMessageComposer
                    topicId={topic.id}
                    topicLocked={topic.state === 'locked'}
                    activeOpenMessage={activeOpenMessage}
                    replyToMessage={replyTarget}
                    onClearReply={() => setReplyTarget(null)}
                    onCommitChanges={onCommitChanges}
                    onStartNewMessage={onStartNewMessage}
                    onCloseOpenMessage={onCloseOpenMessage}
                    onCtrlEnter={handleCtrlEnter}
                    windowDurationSeconds={windowDurationSeconds}
                    inPlace={true}
                  />
                </div>
              );
            }

            // If no replies are below it yet, it is rendered in the bottom composer without unmounting (Bug 1 fix)
            return null;
          }

          // Otherwise render message item
          return (
            <MessageItem
              key={message.id}
              message={message}
              currentUser={currentUser}
              onReply={(msg) => setReplyTarget(msg)}
              onFork={(msg) => onForkToNewTopic(msg, topic)}
              onDeleteMessage={onDeleteMessage}
              onForceClose={onForceCloseMessage}
            />
          );
        })}
      </div>

      {/* Bottom Composer:
          - When no replies are below, this is the author's open message input (or starting input). It NEVER unmounts, preserving focus continuously on Enter! (Bug 1)
          - When replies ARE below, the open message has moved up above them, and this bottom composer appears as a new text input that the user can select to type a new message! (Bug 2)
          - On Ctrl+Enter, bottomComposerKey increments, guaranteeing the new text box is completely clean and empty (Bug fix)!
      */}
      <div className="sticky bottom-4 pt-4">
        <GrowingMessageComposer
          key={`bottom_composer_${bottomComposerKey}`}
          topicId={topic.id}
          topicLocked={topic.state === 'locked'}
          activeOpenMessage={hasRepliesBelow ? null : activeOpenMessage}
          replyToMessage={replyTarget}
          onClearReply={() => setReplyTarget(null)}
          onCommitChanges={onCommitChanges}
          onStartNewMessage={(text, closed) => {
            if (hasRepliesBelow && activeOpenMessage) {
              onCloseOpenMessage();
            }
            onStartNewMessage(text, closed);
          }}
          onCloseOpenMessage={onCloseOpenMessage}
          onCtrlEnter={handleCtrlEnter}
          autoFocusOnMount={bottomComposerKey > 0}
          focusTrigger={bottomFocusTrigger}
          windowDurationSeconds={windowDurationSeconds}
          inPlace={false}
          placeholder={
            hasRepliesBelow
              ? "Type a new message below... · Enter send"
              : "Type here · Enter send · Shift+Enter line break · Ctrl+Enter new line"
          }
        />
      </div>

      {/* Move Category Modal */}
      {showMoveModal && (
        <div className="fixed inset-0 z-50 bg-black/50 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white dark:bg-stone-900 rounded-2xl max-w-sm w-full p-6 shadow-xl border border-stone-200 dark:border-stone-800">
            <h3 className="text-base font-bold text-stone-900 dark:text-stone-100 mb-2">
              Move Topic to Category
            </h3>
            <p className="text-xs text-stone-500 mb-4">
              Select destination category for "{topic.title}":
            </p>
            <div className="space-y-2 mb-6">
              {categories.map((c) => (
                <button
                  key={c.id}
                  onClick={() => {
                    onMoveCategory(topic.id, c.id);
                    setShowMoveModal(false);
                  }}
                  className={`w-full text-left px-3.5 py-2.5 rounded-xl border text-sm font-medium flex items-center justify-between transition-colors ${
                    c.id === category.id
                      ? 'border-orange-500 bg-orange-50 dark:bg-orange-950/40 text-orange-900 dark:text-orange-200'
                      : 'border-stone-200 dark:border-stone-800 hover:bg-stone-50 dark:hover:bg-stone-800'
                  }`}
                >
                  <span className="flex items-center gap-2">
                    <span
                      className="w-2.5 h-2.5 rounded-full"
                      style={{ backgroundColor: c.color }}
                    />
                    <span>{c.name}</span>
                  </span>
                  {c.id === category.id && <Check className="w-4 h-4 text-orange-600" />}
                </button>
              ))}
            </div>
            <div className="flex justify-end">
              <button
                onClick={() => setShowMoveModal(false)}
                className="px-4 py-2 text-xs font-semibold text-stone-600 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 rounded-lg"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
