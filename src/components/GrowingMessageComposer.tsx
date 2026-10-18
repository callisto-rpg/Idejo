import React, { useState, useEffect, useRef } from 'react';
import { Send, X } from 'lucide-react';
import { Message } from '../types';
import { finishSentence, sentRuns } from '../utils/composerLogic';

interface GrowingMessageComposerProps {
  topicId: string;
  topicLocked: boolean;
  activeOpenMessage: Message | null;
  replyToMessage: Message | null;
  onClearReply: () => void;
  onCommitChanges: (newCommittedText: string) => void;
  onStartNewMessage: (text: string, closed?: boolean) => void;
  onCloseOpenMessage: () => void;
  windowDurationSeconds: number;
  inPlace?: boolean;
  placeholder?: string;
  autoFocusOnMount?: boolean;
  focusTrigger?: number;
  onCtrlEnter?: () => void;
}

export const GrowingMessageComposer: React.FC<GrowingMessageComposerProps> = ({
  topicId,
  topicLocked,
  activeOpenMessage,
  replyToMessage,
  onClearReply,
  onCommitChanges,
  onStartNewMessage,
  onCloseOpenMessage,
  windowDurationSeconds,
  inPlace = false,
  placeholder,
  autoFocusOnMount = false,
  focusTrigger,
  onCtrlEnter,
}) => {
  const [currentValue, setCurrentValue] = useState(
    activeOpenMessage?.bodyMd ? activeOpenMessage.bodyMd + ' ' : ''
  );
  const [sentText, setSentText] = useState(
    activeOpenMessage?.bodyMd ? activeOpenMessage.bodyMd + ' ' : ''
  );
  const [remainingSeconds, setRemainingSeconds] = useState<number>(0);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Sync state when activeOpenMessage changes
  useEffect(() => {
    if (activeOpenMessage && activeOpenMessage.state === 'open') {
      const initial = activeOpenMessage.bodyMd.endsWith(' ') || activeOpenMessage.bodyMd.endsWith('\n')
        ? activeOpenMessage.bodyMd
        : activeOpenMessage.bodyMd + ' ';
      setSentText(initial);
      if (!currentValue || !currentValue.startsWith(activeOpenMessage.bodyMd)) {
        setCurrentValue(initial);
      }
    } else if (!activeOpenMessage) {
      setSentText('');
      setCurrentValue('');
      if (textareaRef.current) {
        textareaRef.current.value = '';
      }
    }
  }, [activeOpenMessage?.id, activeOpenMessage?.state]);

  // Window countdown timer running in background (GM-03, GM-04)
  useEffect(() => {
    if (!activeOpenMessage || activeOpenMessage.state !== 'open') {
      setRemainingSeconds(0);
      return;
    }

    const updateTimer = () => {
      const now = Date.now();
      const diff = Math.max(0, Math.ceil((activeOpenMessage.closesAt - now) / 1000));
      setRemainingSeconds(diff);
    };

    updateTimer();
    const interval = setInterval(updateTimer, 500);
    return () => clearInterval(interval);
  }, [activeOpenMessage]);

  const isGrowing = !!activeOpenMessage && activeOpenMessage.state === 'open';

  // Auto-focus on mount if requested
  useEffect(() => {
    if (autoFocusOnMount && textareaRef.current) {
      textareaRef.current.focus();
      const len = textareaRef.current.value.length;
      textareaRef.current.setSelectionRange(len, len);
    }
  }, [autoFocusOnMount]);

  // Focus when focusTrigger changes
  useEffect(() => {
    if (focusTrigger && textareaRef.current) {
      textareaRef.current.focus();
      const len = textareaRef.current.value.length;
      textareaRef.current.setSelectionRange(len, len);
    }
  }, [focusTrigger]);

  // Auto-resize textarea to fit content height dynamically
  useEffect(() => {
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto';
      textareaRef.current.style.height = `${Math.max(48, textareaRef.current.scrollHeight)}px`;
    }
  }, [currentValue]);

  // Compute runs of sent vs unsent text in the background (GM-10)
  const runs = sentRuns(sentText, currentValue);

  // Send function:
  // - On Enter: commits and keeps typing smoothly on same line without losing focus (Bug 1)
  // - On Ctrl+Enter: commits current message, marks it closed where it is, clears input completely, and focuses empty new text box (Bug 2 & Ctrl+Enter fix)
  const handleSend = (isBreak: boolean) => {
    const input = textareaRef.current;
    const caret = input?.selectionStart ?? currentValue.length;

    // --- Ctrl+Enter: Finalize old message where it is, clear input, and move to empty new text box ---
    if (isBreak) {
      const trimmed = currentValue.trim();
      if (trimmed) {
        const body = finishSentence(currentValue);
        if (isGrowing) {
          onCommitChanges(body);
          onCloseOpenMessage();
        } else {
          onStartNewMessage(body, true);
        }
      } else {
        onCloseOpenMessage();
      }

      // Clear text completely so the new text box is EMPTY
      setCurrentValue('');
      setSentText('');
      if (textareaRef.current) {
        textareaRef.current.value = '';
      }

      if (onCtrlEnter) {
        onCtrlEnter();
      } else {
        requestAnimationFrame(() => {
          if (textareaRef.current) {
            textareaRef.current.value = '';
            textareaRef.current.focus();
            textareaRef.current.setSelectionRange(0, 0);
          }
        });
      }
      return;
    }

    // --- Normal Enter: commit on same line and keep typing smoothly without losing focus ---
    const body = finishSentence(currentValue);
    if (body === '') return;

    if (body === sentText.replace(/\s+$/, '')) return;

    const atEnd = caret >= currentValue.replace(/\s+$/, '').length;
    const newValue = body + ' ';

    if (!isGrowing) {
      setSentText(newValue);
      setCurrentValue(newValue);
      onStartNewMessage(body);
    } else {
      setSentText(newValue);
      setCurrentValue(newValue);
      onCommitChanges(body);
    }

    // Retain input focus continuously
    const targetPos = atEnd ? newValue.length : caret;
    if (input) {
      input.focus();
      input.setSelectionRange(targetPos, targetPos);
    }
    requestAnimationFrame(() => {
      if (textareaRef.current) {
        textareaRef.current.focus();
        textareaRef.current.setSelectionRange(targetPos, targetPos);
      }
    });
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key !== 'Enter' || e.shiftKey) return;

    e.preventDefault();
    const isBreak = e.ctrlKey || e.metaKey;
    handleSend(isBreak);
  };

  if (topicLocked) {
    return (
      <div className="p-4 bg-stone-100 dark:bg-stone-900 border border-stone-200 dark:border-stone-800 rounded-xl text-center text-sm text-stone-500">
        This topic has been locked by a moderator. No further messages can be posted.
      </div>
    );
  }

  return (
    <div className="rounded-2xl bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-800 shadow-xs focus-within:border-stone-400 dark:focus-within:border-stone-600 transition-colors overflow-hidden">
      {/* Reply target banner if replying */}
      {replyToMessage && (
        <div className="px-4 py-2 bg-stone-50 dark:bg-stone-950/70 border-b border-stone-200 dark:border-stone-800 flex items-center justify-between text-xs text-stone-600 dark:text-stone-300">
          <div className="flex items-center gap-2 truncate">
            <span className="font-semibold text-stone-700 dark:text-stone-300">
              Replying to {replyToMessage.author.displayName}:
            </span>
            <span className="truncate italic text-stone-500 dark:text-stone-400">
              "{replyToMessage.commits[0]?.text || replyToMessage.bodyMd.slice(0, 50)}"
            </span>
          </div>
          <button
            onClick={onClearReply}
            className="p-1 hover:bg-stone-200 dark:hover:bg-stone-800 rounded text-stone-400 hover:text-stone-600"
            title="Cancel reply"
          >
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
      )}

      {/* Bare, Clean Input Area: Transparent textarea over backdrop */}
      <div className="relative composer-box">
        {/* Backdrop for seamless contrast rendering */}
        <div className="composer-backdrop" aria-hidden="true">
          {runs.length === 0 ? null : (
            runs.map(([text, sent], index) => (
              <span
                key={index}
                className={sent ? "composer-sent font-normal" : "composer-unsent font-normal"}
              >
                {text}
              </span>
            ))
          )}
          {' '}
        </div>

        {/* Textarea input */}
        <textarea
          ref={textareaRef}
          rows={1}
          value={currentValue}
          onChange={(e) => setCurrentValue(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder={
            placeholder ||
            (isGrowing
              ? "Type here... Enter send · Shift+Enter line break · Ctrl+Enter new line"
              : "Type here · Enter send · Shift+Enter line break · Ctrl+Enter new line")
          }
          className="composer-input min-h-[52px]"
        />

        {/* Minimal inline send button for touch/mouse users */}
        {currentValue.trim() && (
          <div className="absolute right-2 bottom-2 z-10 flex items-center gap-1.5">
            <button
              type="button"
              onClick={() => handleSend(false)}
              className="p-1.5 rounded-lg bg-stone-900 text-white dark:bg-stone-100 dark:text-stone-900 hover:opacity-90 transition-opacity shadow-xs"
              title="Send (Enter)"
            >
              <Send className="w-3.5 h-3.5" />
            </button>
          </div>
        )}
      </div>
    </div>
  );
};
