import React, { useState } from 'react';
import { X, Sparkles, Eye, Edit3, GitFork, Info } from 'lucide-react';
import { Category, Message, Topic } from '../types';

interface NewTopicModalProps {
  categories: Category[];
  prefillCategoryId?: string;
  forkFromMessage?: Message | null;
  forkFromTopic?: Topic | null;
  onClose: () => void;
  onCreateTopic: (title: string, categoryId: string, firstMessageBody: string) => void;
}

export const NewTopicModal: React.FC<NewTopicModalProps> = ({
  categories,
  prefillCategoryId,
  forkFromMessage,
  forkFromTopic,
  onClose,
  onCreateTopic,
}) => {
  const [title, setTitle] = useState(
    forkFromTopic ? `Forked discussion: ${forkFromTopic.title}` : ''
  );
  const [categoryId, setCategoryId] = useState<string>(
    prefillCategoryId || categories[0]?.id || ''
  );
  const [firstMessage, setFirstMessage] = useState(
    forkFromMessage
      ? `> ${forkFromMessage.commits[0]?.text || forkFromMessage.bodyMd}\n\nContinuing the discussion on this point here...`
      : ''
  );
  const [previewTab, setPreviewTab] = useState<'write' | 'preview'>('write');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim() || !firstMessage.trim() || !categoryId) return;
    onCreateTopic(title.trim(), categoryId, firstMessage.trim());
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-xs flex items-center justify-center p-4">
      <div className="bg-white dark:bg-stone-900 rounded-3xl max-w-2xl w-full p-6 sm:p-8 shadow-2xl border border-stone-200 dark:border-stone-800 space-y-6 max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between pb-4 border-b border-stone-200 dark:border-stone-800">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl bg-orange-100 dark:bg-orange-950/60 text-orange-600 dark:text-orange-400 flex items-center justify-center">
              {forkFromMessage ? <GitFork className="w-4 h-4" /> : <Edit3 className="w-4 h-4" />}
            </div>
            <div>
              <h2 className="text-lg font-bold text-stone-900 dark:text-stone-50 font-serif">
                {forkFromMessage ? 'Fork into New Topic' : 'Start a New Topic'}
              </h2>
              <span className="text-xs text-stone-500">
                {forkFromMessage ? 'Branches a specific message into its own thread (TP-09)' : 'Create a fresh discussion topic (TP-01, TP-02)'}
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

        {/* Invariant GM-14 Callout Banner */}
        <div className="p-3 bg-stone-50 dark:bg-stone-950/60 border border-stone-200/80 dark:border-stone-800 rounded-xl flex items-start gap-2.5 text-xs text-stone-600 dark:text-stone-400">
          <Info className="w-4 h-4 text-orange-500 shrink-0 mt-0.5" />
          <div>
            <strong className="text-stone-800 dark:text-stone-200 font-semibold">Invariant GM-14:</strong> The first message of a topic is posted immediately as a closed message. Subsequent replies in the topic will use the live Growing Message window.
          </div>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          {/* Category Selector */}
          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-stone-500 mb-1.5">
              Category
            </label>
            <select
              value={categoryId}
              onChange={(e) => setCategoryId(e.target.value)}
              className="w-full px-3.5 py-2.5 bg-stone-50 dark:bg-stone-800 border border-stone-200 dark:border-stone-700 rounded-xl text-sm font-medium text-stone-900 dark:text-stone-100 focus:outline-none focus:ring-2 focus:ring-orange-500/20"
            >
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>

          {/* Topic Title */}
          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-stone-500 mb-1.5">
              Topic Title
            </label>
            <input
              type="text"
              required
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="What is this topic about?"
              className="w-full px-3.5 py-2.5 bg-stone-50 dark:bg-stone-800 border border-stone-200 dark:border-stone-700 rounded-xl text-sm font-medium text-stone-900 dark:text-stone-100 placeholder-stone-400 focus:outline-none focus:ring-2 focus:ring-orange-500/20"
            />
          </div>

          {/* First Message & Tabs */}
          <div>
            <div className="flex items-center justify-between mb-1.5">
              <label className="block text-xs font-semibold uppercase tracking-wider text-stone-500">
                First Message (Markdown supported)
              </label>

              <div className="flex items-center p-0.5 bg-stone-100 dark:bg-stone-800 rounded-lg text-xs font-medium">
                <button
                  type="button"
                  onClick={() => setPreviewTab('write')}
                  className={`px-2.5 py-1 rounded-md transition-colors flex items-center gap-1 ${
                    previewTab === 'write'
                      ? 'bg-white dark:bg-stone-900 text-stone-900 dark:text-stone-100 shadow-xs'
                      : 'text-stone-500'
                  }`}
                >
                  <Edit3 className="w-3 h-3" />
                  <span>Write</span>
                </button>
                <button
                  type="button"
                  onClick={() => setPreviewTab('preview')}
                  className={`px-2.5 py-1 rounded-md transition-colors flex items-center gap-1 ${
                    previewTab === 'preview'
                      ? 'bg-white dark:bg-stone-900 text-stone-900 dark:text-stone-100 shadow-xs'
                      : 'text-stone-500'
                  }`}
                >
                  <Eye className="w-3 h-3" />
                  <span>Preview</span>
                </button>
              </div>
            </div>

            {previewTab === 'write' ? (
              <textarea
                required
                rows={5}
                value={firstMessage}
                onChange={(e) => setFirstMessage(e.target.value)}
                placeholder="Write the opening post of your topic..."
                className="w-full px-3.5 py-2.5 bg-stone-50 dark:bg-stone-800 border border-stone-200 dark:border-stone-700 rounded-xl text-sm text-stone-900 dark:text-stone-100 placeholder-stone-400 focus:outline-none focus:ring-2 focus:ring-orange-500/20 leading-relaxed font-sans"
              />
            ) : (
              <div className="w-full min-h-[120px] p-3.5 bg-stone-50 dark:bg-stone-950/70 border border-stone-200 dark:border-stone-800 rounded-xl text-sm text-stone-800 dark:text-stone-200 whitespace-pre-wrap leading-relaxed">
                {firstMessage.trim() ? firstMessage : <span className="italic text-stone-400">Nothing to preview</span>}
              </div>
            )}
          </div>

          <div className="flex items-center justify-end gap-3 pt-4 border-t border-stone-200 dark:border-stone-800">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-xs font-semibold text-stone-600 dark:text-stone-400 hover:bg-stone-100 dark:hover:bg-stone-800 rounded-xl transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={!title.trim() || !firstMessage.trim()}
              className="px-5 py-2 bg-orange-600 hover:bg-orange-700 disabled:opacity-50 text-white text-xs font-semibold rounded-xl shadow-sm shadow-orange-600/30 transition-all"
            >
              Post New Topic
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
