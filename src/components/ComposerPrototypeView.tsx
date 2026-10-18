import React, { useState } from 'react';
import { User, Message } from '../types';
import { GrowingMessageComposer } from './GrowingMessageComposer';
import { Users, Sparkles, RefreshCw, Plus } from 'lucide-react';

interface ComposerPrototypeViewProps {
  currentUser: User;
  onSwitchUser?: (name: string, role: string) => void;
}

export const ComposerPrototypeView: React.FC<ComposerPrototypeViewProps> = ({
  currentUser,
}) => {
  // Prototype in-memory state as defined in Idejo.Messages.DemoTopic
  const [authorName, setAuthorName] = useState(currentUser.displayName);
  const [authorRole, setAuthorRole] = useState(currentUser.roleTitle || 'Member');
  
  const [messages, setMessages] = useState<Array<{
    id: number;
    author: { id: string; name: string; role: string };
    body: string;
    state: 'open' | 'closed';
    openedAt: number;
    closesAt: number;
  }>>([
    {
      id: 1,
      author: { id: 'usr_ana', name: 'Ana', role: 'Moderator' },
      body: 'Welcome to the composer prototype. Try typing below: Enter commits your changes, adds punctuation, and keeps typing on the same line.',
      state: 'closed',
      openedAt: Date.now() - 60000,
      closesAt: Date.now() - 15000,
    },
    {
      id: 2,
      author: { id: 'usr_bob', name: 'Bob', role: 'Member' },
      body: 'Replies appear below your composer, pushing your open message up.',
      state: 'closed',
      openedAt: Date.now() - 40000,
      closesAt: Date.now() + 5000,
    },
  ]);

  const authorId = `usr_${authorName.toLowerCase().replace(/\s+/g, '_')}`;

  // Find user's open message in this prototype topic
  const myOpenMsg = messages.find(m => m.state === 'open' && m.author.id === authorId);

  // Split messages as defined in DemoTopicLive: {before, mine, rest}
  const splitIndex = myOpenMsg ? messages.findIndex(m => m.id === myOpenMsg.id) : -1;
  const beforeMessages = splitIndex >= 0 ? messages.slice(0, splitIndex) : messages;
  const restMessages = splitIndex >= 0 ? messages.slice(splitIndex + 1) : [];

  const [protoComposerKey, setProtoComposerKey] = useState(0);
  const [protoFocusTrigger, setProtoFocusTrigger] = useState(0);

  const handleProtoCtrlEnter = () => {
    handleCloseMessage();
    setProtoComposerKey((k) => k + 1);
    setProtoFocusTrigger((t) => t + 1);
  };

  const handleStartMessage = (text: string, closed = false) => {
    const now = Date.now();
    const newMsg = {
      id: messages.length + 1,
      author: { id: authorId, name: authorName, role: authorRole },
      body: text,
      state: (closed ? 'closed' : 'open') as const,
      openedAt: now,
      closesAt: closed ? now : now + 45000,
    };
    setMessages(prev => [...prev, newMsg]);
  };

  const handleCommitChanges = (newBody: string) => {
    setMessages(prev =>
      prev.map(m =>
        m.state === 'open' && m.author.id === authorId
          ? { ...m, body: newBody }
          : m
      )
    );
  };

  const handleCloseMessage = () => {
    setMessages(prev =>
      prev.map(m =>
        m.state === 'open' && m.author.id === authorId
          ? { ...m, state: 'closed' as const }
          : m
      )
    );
  };

  const handleSimulateReply = () => {
    const peers = [
      { name: 'Elena', role: 'Moderator', text: 'Looks great! The auto-period and backdrop contrast work seamlessly.' },
      { name: 'Lucas', role: 'Member', text: 'Notice how this reply appeared below your composer, pushing it up!' },
      { name: 'Sophia', role: 'Member', text: 'Typing feels so smooth with Enter keeping you on the same line.' },
    ];
    const pick = peers[Math.floor(Math.random() * peers.length)];
    const now = Date.now();
    setMessages(prev => [
      ...prev,
      {
        id: prev.length + 1,
        author: { id: `peer_${Date.now()}`, name: pick.name, role: pick.role },
        body: pick.text,
        state: 'closed',
        openedAt: now,
        closesAt: now,
      },
    ]);
  };

  // Convert for GrowingMessageComposer prop compatibility
  const activeOpenConverted: Message | null = myOpenMsg
    ? {
        id: `proto_${myOpenMsg.id}`,
        uri: `idejo://proto/${myOpenMsg.id}`,
        topicId: 'proto',
        author: {
          id: authorId,
          uri: `idejo://users/${authorId}`,
          displayName: authorName,
          email: `${authorId}@example.com`,
          role: 'member',
          avatar: '',
        },
        state: 'open',
        openedAt: myOpenMsg.openedAt,
        closesAt: myOpenMsg.closesAt,
        commits: [{ id: '1', position: 1, text: myOpenMsg.body, createdAt: 'now' }],
        bodyMd: myOpenMsg.body,
      }
    : null;

  const initials = (name: string) =>
    name
      .split(' ')
      .slice(0, 2)
      .map(w => w[0] || '')
      .join('')
      .toUpperCase();

  return (
    <div className="max-w-3xl mx-auto px-4 sm:px-6 py-8 space-y-6">
      {/* Top Banner */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-4 border-b border-stone-200 dark:border-stone-800">
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-xl font-bold tracking-tight text-stone-900 dark:text-stone-50 font-serif">
              Composer Prototype (/dev/topic)
            </h1>
            <span className="px-2 py-0.5 rounded text-[10px] font-semibold bg-orange-100 text-orange-800 dark:bg-orange-950 dark:text-orange-300">
              PR #4 upstream
            </span>
          </div>
          <p className="text-xs text-stone-500 mt-1">
            Test the composer before M3. The text box is your open message. Sent text is rendered in higher contrast than unsent text.
          </p>
        </div>

        {/* Identity & Simulation Switcher */}
        <div className="flex items-center gap-2">
          <button
            onClick={handleSimulateReply}
            className="px-3 py-1.5 bg-stone-100 dark:bg-stone-800 hover:bg-stone-200 dark:hover:bg-stone-700 text-stone-700 dark:text-stone-200 text-xs font-semibold rounded-lg flex items-center gap-1.5 border border-stone-200 dark:border-stone-700"
            title="Simulate someone else replying below your composer"
          >
            <Plus className="w-3.5 h-3.5 text-orange-500" />
            <span>Simulate Reply</span>
          </button>
        </div>
      </div>

      {/* Author Bar */}
      <div className="p-3 bg-stone-100/70 dark:bg-stone-900/60 rounded-xl border border-stone-200 dark:border-stone-800 flex items-center justify-between text-xs">
        <div className="flex items-center gap-3">
          <span className="w-7 h-7 rounded-full bg-stone-800 text-white flex items-center justify-center font-bold text-xs">
            {initials(authorName)}
          </span>
          <div className="flex items-center gap-2">
            <span className="font-semibold text-stone-900 dark:text-stone-100">{authorName}</span>
            <span className="text-stone-500">({authorRole})</span>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <span className="text-stone-400">Switch persona:</span>
          <button
            onClick={() => { setAuthorName('Mariano'); setAuthorRole('Admin'); }}
            className={`px-2 py-1 rounded text-xs ${authorName === 'Mariano' ? 'bg-orange-600 text-white font-bold' : 'bg-stone-200 dark:bg-stone-800'}`}
          >
            Mariano
          </button>
          <button
            onClick={() => { setAuthorName('Elena'); setAuthorRole('Moderator'); }}
            className={`px-2 py-1 rounded text-xs ${authorName === 'Elena' ? 'bg-orange-600 text-white font-bold' : 'bg-stone-200 dark:bg-stone-800'}`}
          >
            Elena
          </button>
          <button
            onClick={() => { setAuthorName('Guest 42'); setAuthorRole('Member'); }}
            className={`px-2 py-1 rounded text-xs ${authorName === 'Guest 42' ? 'bg-orange-600 text-white font-bold' : 'bg-stone-200 dark:bg-stone-800'}`}
          >
            Guest
          </button>
        </div>
      </div>

      {/* Messages & In-place composer container */}
      <div id="topic" className="flex flex-col gap-4">
        {/* Messages before open message */}
        <div id="before" className="flex flex-col gap-4">
          {beforeMessages.map((m) => (
            <article key={m.id} id={`m${m.id}`} className="flex flex-col gap-1 p-3 rounded-xl bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-800">
              <div className="flex items-center gap-3">
                <span className="flex size-7 shrink-0 items-center justify-center rounded-full bg-stone-700 text-xs font-semibold text-white">
                  {initials(m.author.name)}
                </span>
                <span className="font-semibold text-sm text-stone-900 dark:text-stone-100">{m.author.name}</span>
                <span className="text-xs text-stone-400">{m.author.role}</span>
              </div>
              <p className="whitespace-pre-wrap break-words pl-10 text-sm text-stone-800 dark:text-stone-200">
                {m.body}
                {m.state === 'open' && (
                  <span className="text-xs text-orange-500 font-medium ml-2">(still being written)</span>
                )}
              </p>
            </article>
          ))}
        </div>

        {/* Composer Slot (GM-08: In-place of author's open message) */}
        <div id="composer-slot" className="flex flex-col gap-1">
          {myOpenMsg && (
            <div className="flex items-center gap-3 pb-1">
              <span className="flex size-7 shrink-0 items-center justify-center rounded-full bg-orange-600 text-xs font-semibold text-white">
                {initials(authorName)}
              </span>
              <span className="font-semibold text-sm text-stone-900 dark:text-stone-100">{authorName}</span>
              <span className="text-xs text-stone-400">{authorRole}</span>
            </div>
          )}

          <GrowingMessageComposer
            key={`proto_slot_${protoComposerKey}`}
            topicId="proto"
            topicLocked={false}
            activeOpenMessage={activeOpenConverted}
            replyToMessage={null}
            onClearReply={() => {}}
            onCommitChanges={handleCommitChanges}
            onStartNewMessage={handleStartMessage}
            onCloseOpenMessage={handleCloseMessage}
            onCtrlEnter={handleProtoCtrlEnter}
            autoFocusOnMount={protoComposerKey > 0}
            focusTrigger={protoFocusTrigger}
            windowDurationSeconds={45}
            inPlace={!!myOpenMsg}
          />
        </div>

        {/* Messages after open message (Replies from others that appear below) */}
        <div id="after" className="flex flex-col gap-4">
          {restMessages.map((m) => (
            <article key={m.id} id={`m${m.id}`} className="flex flex-col gap-1 p-3 rounded-xl bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-800">
              <div className="flex items-center gap-3">
                <span className="flex size-7 shrink-0 items-center justify-center rounded-full bg-stone-700 text-xs font-semibold text-white">
                  {initials(m.author.name)}
                </span>
                <span className="font-semibold text-sm text-stone-900 dark:text-stone-100">{m.author.name}</span>
                <span className="text-xs text-stone-400">{m.author.role}</span>
              </div>
              <p className="whitespace-pre-wrap break-words pl-10 text-sm text-stone-800 dark:text-stone-200">
                {m.body}
              </p>
            </article>
          ))}
        </div>

        {/* When replies are below, a new text input appears below them (Bug 2) */}
        {restMessages.length > 0 && (
          <div className="pt-2">
            <GrowingMessageComposer
              key={`proto_bottom_${protoComposerKey}`}
              topicId="proto"
              topicLocked={false}
              activeOpenMessage={null}
              replyToMessage={null}
              onClearReply={() => {}}
              onCommitChanges={() => {}}
              onStartNewMessage={(text, closed) => {
                handleCloseMessage();
                handleStartMessage(text, closed);
              }}
              onCloseOpenMessage={handleCloseMessage}
              onCtrlEnter={handleProtoCtrlEnter}
              autoFocusOnMount={protoComposerKey > 0}
              focusTrigger={protoFocusTrigger}
              windowDurationSeconds={45}
              inPlace={false}
              placeholder="Type a new message below... · Enter send"
            />
          </div>
        )}
      </div>
    </div>
  );
};
