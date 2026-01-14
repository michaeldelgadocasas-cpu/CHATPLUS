#!/bin/bash
set -e

REPO_OWNER="michaeldelgadocasas-cpu"
REPO_NAME="ChatPlus"
COMMIT_MSG="Initial ChatPlus scaffold with calling"

mkdir -p "$REPO_NAME"
cd "$REPO_NAME"

# Create files and directories with exact contents
cat > README.md <<'EOF'
# ChatPlus

MVP: Mensajería en tiempo real con grupos, imágenes, notas de voz, y llamadas (voz/video) usando WebRTC. Backend: Node.js + Express + Socket.IO + Prisma + PostgreSQL. Cliente móvil: React Native (react-native-cli) con react-native-webrtc para llamadas.

Instrucciones rápidas de setup se encuentran en backend/README.md y mobile/README.md.
EOF

cat > .gitignore <<'EOF'
node_modules/
.env
android/
ios/
.DS_Store
dist/
EOF

mkdir -p backend/src/controllers backend/prisma
cat > backend/package.json <<'EOF'
{
  "name": "chatplus-backend",
  "version": "0.1.0",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "@prisma/client": "^4.0.0",
    "cors": "^2.8.5",
    "express": "^4.18.2",
    "multer": "^1.4.5",
    "socket.io": "^4.7.2",
    "ws": "^8.13.0"
  },
  "devDependencies": {
    "nodemon": "^2.0.20",
    "prisma": "^4.0.0"
  }
}
EOF

cat > backend/server.js <<'EOF'
const express = require('express');
const http = require('http');
const cors = require('cors');
const { PrismaClient } = require('@prisma/client');
const { createServer } = require('http');
const { Server } = require('socket.io');
const uploadsRouter = require('./src/controllers/uploads');
const chatSocket = require('./src/sockets/chatSocket');

const prisma = new PrismaClient();
const app = express();
app.use(cors());
app.use(express.json());

app.post('/auth/login', async (req, res) => {
  const { userId, name } = req.body;
  res.json({ userId, name, token: 'DEV_TOKEN' });
});

app.use('/uploads', uploadsRouter);

app.get('/chats/:chatId/messages', async (req, res) => {
  const { chatId } = req.params;
  const messages = await prisma.message.findMany({
    where: { chatId: Number(chatId) },
    orderBy: { createdAt: 'asc' },
    take: 100,
  });
  res.json(messages);
});

const server = createServer(app);
const io = new Server(server, { cors: { origin: '*' } });

chatSocket(io, prisma);

const PORT = process.env.PORT || 4000;
server.listen(PORT, () => {
  console.log(`ChatPlus backend listening on ${PORT}`);
});
EOF

cat > backend/prisma/schema.prisma <<'EOF'
generator client {
  provider = "prisma-client-js"
}
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        Int      @id @default(autoincrement())
  externalId String  @unique
  name      String
  avatarUrl String?
  createdAt DateTime @default(now())
  memberships Membership[]
  messages  Message[]
}

model Chat {
  id        Int      @id @default(autoincrement())
  title     String?
  isGroup   Boolean  @default(false)
  createdAt DateTime @default(now())
  memberships Membership[]
  messages  Message[]
}

model Membership {
  id     Int  @id @default(autoincrement())
  user   User @relation(fields: [userId], references: [id])
  userId Int
  chat   Chat @relation(fields: [chatId], references: [id])
  chatId Int
  role   String @default("member")
}

model Message {
  id         Int      @id @default(autoincrement())
  chat       Chat     @relation(fields: [chatId], references: [id])
  chatId     Int
  sender     User     @relation(fields: [senderId], references: [id])
  senderId   Int
  content    String?
  type       String   @default("text")
  mediaUrl   String?
  durationMs Int?
  createdAt  DateTime @default(now())
  delivered  Boolean  @default(false)
  read       Boolean  @default(false)
}
EOF

cat > backend/src/sockets/chatSocket.js <<'EOF'
module.exports = function chatSocket(io, prisma) {
  io.on('connection', (socket) => {
    console.log('Socket connected:', socket.id);

    socket.on('join', async ({ chatId, userId }) => {
      socket.join(`chat_${chatId}`);
      socket.to(`chat_${chatId}`).emit('presence', { userId, status: 'online' });
    });

    socket.on('leave', ({ chatId, userId }) => {
      socket.leave(`chat_${chatId}`);
      socket.to(`chat_${chatId}`).emit('presence', { userId, status: 'offline' });
    });

    socket.on('message:send', async (payload, ack) => {
      try {
        const message = await prisma.message.create({
          data: {
            chatId: Number(payload.chatId),
            senderId: Number(payload.senderId),
            content: payload.content,
            type: payload.type || 'text',
            mediaUrl: payload.mediaUrl || null,
            durationMs: payload.durationMs || null
          }
        });
        io.to(`chat_${payload.chatId}`).emit('message:new', message);
        if (ack) ack({ ok: true, message });
      } catch (err) {
        console.error('Error saving message', err);
        if (ack) ack({ ok: false, error: err.message });
      }
    });

    socket.on('signal', ({ to, from, data }) => {
      // Signaling for WebRTC
      socket.to(to).emit('signal', { from, data });
    });

    socket.on('disconnect', () => {
      console.log('Socket disconnected:', socket.id);
    });
  });
};
EOF

cat > backend/src/controllers/uploads.js <<'EOF'
const express = require('express');
const multer = require('multer');
const router = express.Router();

const storage = multer.memoryStorage();
const upload = multer({ storage });

router.post('/image', upload.single('file'), async (req, res) => {
  const fakeUrl = `https://cdn.example.com/images/${Date.now()}_${req.file.originalname}`;
  res.json({ url: fakeUrl });
});

router.post('/voice', upload.single('file'), async (req, res) => {
  const fakeUrl = `https://cdn.example.com/voices/${Date.now()}_${req.file.originalname}`;
  res.json({ url: fakeUrl, durationMs: req.body.durationMs || null });
});

module.exports = router;
EOF

mkdir -p mobile/src/screens mobile/src/services
cat > mobile/README.md <<'EOF'
# Mobile (React Native)

Este cliente usa react-native CLI (no Expo) para poder integrar react-native-webrtc.

Pasos:
1. Instalar dependencias: npm install
2. iOS: cd ios && pod install
3. Ejecutar en emulador: npx react-native run-ios o run-android

Incluye ejemplo de llamadas usando react-native-webrtc y signaling por Socket.IO.
EOF

cat > mobile/package.json <<'EOF'
{
  "name": "chatplus-mobile",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "android": "npx react-native run-android",
    "ios": "npx react-native run-ios"
  },
  "dependencies": {
    "react": "18.2.0",
    "react-native": "0.71.8",
    "socket.io-client": "^4.7.2",
    "axios": "^1.4.0",
    "react-native-webrtc": "~1.94.0",
    "@react-native-async-storage/async-storage": "^1.17.11",
    "react-native-permissions": "^3.8.0"
  }
}
EOF

cat > mobile/App.js <<'EOF'
import React from 'react';
import { SafeAreaView } from 'react-native';
import CallScreen from './src/screens/CallScreen';

export default function App() {
  return (
    <SafeAreaView style={{ flex: 1 }}>
      <CallScreen />
    </SafeAreaView>
  );
}
EOF

cat > mobile/src/screens/CallScreen.js <<'EOF'
import React, { useEffect, useRef, useState } from 'react';
import { View, Button, Text } from 'react-native';
import { RTCPeerConnection, mediaDevices, RTCView } from 'react-native-webrtc';
import { connectSocket, getSocket } from '../services/socket';

const pcConfig = { iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] };

export default function CallScreen() {
  const [localStream, setLocalStream] = useState(null);
  const [remoteStream, setRemoteStream] = useState(null);
  const pcRef = useRef(null);
  const socketRef = useRef(null);
  const myId = Math.random().toString(36).slice(2,9);

  useEffect(() => {
    socketRef.current = connectSocket({ serverUrl: 'http://YOUR_SERVER:4000', token: 'DEV_TOKEN' });
    socketRef.current.on('signal', async ({ from, data }) => {
      if (data.type === 'offer') {
        // create pc if needed
        await ensurePc();
        await pcRef.current.setRemoteDescription(data);
        const answer = await pcRef.current.createAnswer();
        await pcRef.current.setLocalDescription(answer);
        socketRef.current.emit('signal', { to: from, from: myId, data: pcRef.current.localDescription });
      } else if (data.type === 'answer') {
        await pcRef.current.setRemoteDescription(data);
      } else if (data.candidate) {
        await pcRef.current.addIceCandidate(data);
      }
    });

    return () => {
      if (pcRef.current) pcRef.current.close();
      if (localStream) localStream.release && localStream.release();
      socketRef.current && socketRef.current.disconnect();
    };
  }, []);

  const ensurePc = async () => {
    if (pcRef.current) return;
    const pc = new RTCPeerConnection(pcConfig);
    pc.onicecandidate = (e) => {
      if (e.candidate) socketRef.current.emit('signal', { to: 'PEER_ID', from: myId, data: e.candidate });
    };
    pc.ontrack = (e) => setRemoteStream(e.streams[0]);
    pcRef.current = pc;
  };

  const startLocal = async () => {
    const stream = await mediaDevices.getUserMedia({ audio: true, video: true });
    setLocalStream(stream);
    await ensurePc();
    stream.getTracks().forEach((t) => pcRef.current.addTrack(t, stream));
  };

  const callPeer = async (peerId) => {
    await ensurePc();
    const offer = await pcRef.current.createOffer();
    await pcRef.current.setLocalDescription(offer);
    socketRef.current.emit('signal', { to: peerId, from: myId, data: pcRef.current.localDescription });
  };

  return (
    <View style={{ flex: 1, padding: 12 }}>
      <Button title="Start local" onPress={startLocal} />
      <Button title="Call peer (replace PEER_ID)" onPress={() => callPeer('PEER_ID')} />
      {localStream && <RTCView streamURL={localStream.toURL()} style={{ width: 200, height: 150 }} />}
      {remoteStream && <RTCView streamURL={remoteStream.toURL()} style={{ width: 200, height: 150 }} />}
    </View>
  );
}
EOF

cat > mobile/src/services/socket.js <<'EOF'
import io from 'socket.io-client';
let socket = null;
export const connectSocket = ({ serverUrl, token }) => {
  socket = io(serverUrl, { auth: { token } });
  socket.on('connect', () => console.log('Socket connected', socket.id));
  return socket;
};
export const getSocket = () => socket;
EOF

# Initialize git, commit, and create GitHub repo using gh
git init
git add .
git commit -m "$COMMIT_MSG"

# Create repo on GitHub under the specified owner and push
gh repo create "$REPO_OWNER/$REPO_NAME" --public --source=. --remote=origin --push

echo "Repository created and pushed: https://github.com/$REPO_OWNER/$REPO_NAME"