import React, { useState } from 'react';
import { 
  Reply, 
  GitFork, 
  Link as LinkIcon, 
  Flag, 
  Trash2, 
  Clock, 
  Check, 
  History, 
  ShieldAlert, 
  CornerDownRight,
  Sparkles
} from 'lucide-react';
import { Message, User } from '../types';

interface MessageItemProps {
  message: Message;
  currentUser: User;
  onReply: (message: Message) => void;
  onFork: (message: Message) => void;
  onDeleteMessage?: (messageId: string) => void;
  onForceClose?: (messageId: string) => void;
  highlighted?: boolean;
}

export const MessageItem: React.FC<MessageItemProps> = ({
  message,
  currentUser,
  onReply,
  onFork,
  onDeleteMessage,
  onForceClose,
  highlighted,
}) => {
  const [copiedLink, setCopiedLink] = useState(false);
  const [showHistory, setShowHistory] = useState(false);
  const [reported, setReported] = useState(false);

  const isAuthor = currentUser.id === message.author.id;
  const isModOrAdmin = currentUser.role === 'admin' || currentUser.role === 'moderator';
  const isOpen = message.state === 'open';

  const handleCopyLink = () => {
    navigator.clipboard?.writeText(window.location.origin + '#' + message.id);
    setCopiedLink(true);
    setTimeout(() => setCopiedLink(false), 2000);
  };

  const handleReport = () => {
    const reason = window.prompt("Reason for reporting this message:");
    if (reason) {
      setReported(true);
      window.alert("Thank you. The report has been submitted to the community moderation queue.");
    }
  };

  // Render markdown text simply and cleanly
  const renderFormattedText = (text: string) => {
    // Split into paragraphs
    const paragraphs = text.split('\n\n');
    return paragraphs.map((para, pIdx) => {
      const lines = para.split('\n');
      return (
        <p key={pIdx} className="mb-2 last:mb-0 leading-relaxed text-stone-800 dark:text-stone-200">
          {lines.map((line, lIdx) => {
            // Check for bold and inline code
            let formattedLine: React.ReactNode = line;

            // Simple parser for `code`
            const codeParts = line.split(/(`[^`]+`)/g);
            if (codeParts.length > 1) {
              formattedLine = codeParts.map((part, i) => {
                if (part.startsWith('`') && part.endsWith('`')) {
                  return (
                    <code
                      key={i}
                      className="px-1.5 py-0.5 mx-0.5 font-mono text-xs bg-stone-100 dark:bg-stone-800 text-orange-600 dark:text-orange-400 rounded border border-stone-200/60 dark:border-stone-700"
                    >
                      {part.slice(1, -1)}
                    </code>
                  );
                }
                // Handle **bold**
                return part;
              });
            }

            return (
              <React.Fragment key={lIdx}>
                {formattedLine}
                {lIdx < lines.length - 1 && <br />}
              </React.Fragment>
            );
          })}
        </p>
      );
    });
  };

  return (
    <article
      id={message.id}
      className={`group relative p-4 sm:p-5 rounded-2xl transition-all duration-200 ${
        isOpen
          ? 'bg-orange-50/70 dark:bg-orange-950/20 border-2 border-orange-400 dark:border-orange-600 shadow-sm'
          : highlighted
          ? 'bg-amber-50/50 dark:bg-amber-950/20 border border-amber-300 dark:border-amber-700'
          : 'bg-white dark:bg-stone-900 border border-stone-200/80 dark:border-stone-800 hover:border-stone-300 dark:hover:border-stone-700'
      }`}
    >
      {/* Inline Reply reference banner if this was a reply */}
      {message.replyToAuthor && (
        <div className="mb-3 px-3 py-1.5 rounded-lg bg-stone-100/80 dark:bg-stone-800/60 border border-stone-200/60 dark:border-stone-700/60 flex items-center gap-2 text-xs text-stone-600 dark:text-stone-300">
          <CornerDownRight className="w-3.5 h-3.5 text-orange-500 shrink-0" />
          <span className="font-semibold text-orange-600 dark:text-orange-400">
            {message.replyToAuthor}
          </span>
          <span className="truncate italic text-stone-500 dark:text-stone-400">
            {message.replyToSnippet || '...'}
          </span>
        </div>
      )}

      {/* Header: Author & Metadata */}
      <div className="flex items-start justify-between gap-3 mb-2.5">
        <div className="flex items-center gap-3">
          <img
            src={message.author.avatar}
            alt={message.author.displayName}
            className="w-10 h-10 rounded-full object-cover ring-2 ring-stone-200 dark:ring-stone-800"
          />
          <div>
            <div className="flex items-center gap-2 flex-wrap">
              <span className="font-semibold text-sm text-stone-900 dark:text-stone-100">
                {message.author.displayName}
              </span>

              {/* Role badge */}
              <span
                className="px-2 py-0.5 text-[10px] font-semibold rounded-full uppercase tracking-wider"
                style={{
                  backgroundColor: `${message.author.roleColor || '#f97316'}20`,
                  color: message.author.roleColor || '#f97316',
                }}
              >
                {message.author.roleTitle || message.author.role}
              </span>
            </div>

            <div className="flex items-center gap-2 text-xs text-stone-400 dark:text-stone-500 mt-0.5">
              <span>{new Date(message.openedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span>
              <span>&bull;</span>
              <span className="font-mono text-[10px] text-stone-400">
                {message.uri}
              </span>
              {message.commits && message.commits.length > 1 && (
                <>
                  <span>&bull;</span>
                  <span className="text-orange-600 dark:text-orange-400 font-medium">
                    {message.commits.length} commits merged
                  </span>
                </>
              )}
            </div>
          </div>
        </div>

        {/* Top-Right: Quick actions */}
        <div className="flex items-center gap-1 opacity-80 sm:opacity-0 sm:group-hover:opacity-100 transition-opacity">
          <button
            onClick={handleCopyLink}
            className="p-1.5 text-stone-400 hover:text-stone-700 dark:hover:text-stone-200 hover:bg-stone-100 dark:hover:bg-stone-800 rounded-md transition-colors"
            title="Copy permalink URI"
          >
            {copiedLink ? <Check className="w-4 h-4 text-emerald-500" /> : <LinkIcon className="w-4 h-4" />}
          </button>

          <button
            onClick={() => onReply(message)}
            className="p-1.5 text-stone-400 hover:text-orange-600 dark:hover:text-orange-400 hover:bg-stone-100 dark:hover:bg-stone-800 rounded-md transition-colors"
            title="Reply inline (TP-08)"
          >
            <Reply className="w-4 h-4" />
          </button>

          <button
            onClick={() => onFork(message)}
            className="p-1.5 text-stone-400 hover:text-amber-600 dark:hover:text-amber-400 hover:bg-stone-100 dark:hover:bg-stone-800 rounded-md transition-colors"
            title="New topic from this message (Fork TP-09)"
          >
            <GitFork className="w-4 h-4" />
          </button>

          <button
            onClick={handleReport}
            disabled={reported}
            className="p-1.5 text-stone-400 hover:text-red-500 hover:bg-stone-100 dark:hover:bg-stone-800 rounded-md transition-colors"
            title="Report message (MO-01)"
          >
            <Flag className={`w-4 h-4 ${reported ? 'text-red-500 fill-current' : ''}`} />
          </button>

          {isModOrAdmin && onDeleteMessage && (
            <button
              onClick={() => onDeleteMessage(message.id)}
              className="p-1.5 text-stone-400 hover:text-red-600 hover:bg-stone-100 dark:hover:bg-stone-800 rounded-md transition-colors"
              title="Moderator: Delete message"
            >
              <Trash2 className="w-4 h-4" />
            </button>
          )}
        </div>
      </div>

      {/* Message Body */}
      <div className="text-sm pl-0 sm:pl-13">
        {renderFormattedText(message.bodyMd)}

        {/* GM-11 Version History button if message was edited */}
        {message.edited && (
          <div className="mt-2.5 pt-2 border-t border-stone-100 dark:border-stone-800 flex items-center gap-2">
            <button
              onClick={() => setShowHistory(!showHistory)}
              className="inline-flex items-center gap-1 text-xs text-stone-400 hover:text-orange-600 dark:hover:text-orange-400 font-medium transition-colors"
            >
              <History className="w-3.5 h-3.5" />
              <span>{showHistory ? 'Hide earlier version' : 'View earlier version (GM-11)'}</span>
            </button>
          </div>
        )}

        {/* Earlier Version Expanded View */}
        {showHistory && message.versions && message.versions.length > 0 && (
          <div className="mt-2 p-3 bg-stone-50 dark:bg-stone-950 rounded-xl border border-dashed border-stone-300 dark:border-stone-700 text-xs text-stone-600 dark:text-stone-400">
            <div className="font-semibold text-stone-700 dark:text-stone-300 mb-1 flex items-center gap-1.5">
              <span>Original version prior to edit:</span>
              <span className="text-[10px] text-stone-400">({message.versions[0].createdAt})</span>
            </div>
            <p className="italic bg-white dark:bg-stone-900 p-2 rounded border border-stone-200 dark:border-stone-800">
              "{message.versions[0].bodyMd}"
            </p>
          </div>
        )}
      </div>

      {/* Footer bar for mobile quick reply */}
      <div className="mt-3 pt-2 border-t border-stone-100 dark:border-stone-800/80 flex items-center justify-between sm:hidden text-xs text-stone-500">
        <button
          onClick={() => onReply(message)}
          className="flex items-center gap-1 text-orange-600 dark:text-orange-400 font-medium"
        >
          <Reply className="w-3.5 h-3.5" />
          <span>Reply</span>
        </button>
        <button
          onClick={() => onFork(message)}
          className="flex items-center gap-1 text-stone-600 dark:text-stone-400"
        >
          <GitFork className="w-3.5 h-3.5" />
          <span>Fork to Topic</span>
        </button>
      </div>
    </article>
  );
};
