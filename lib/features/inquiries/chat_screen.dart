import 'package:flutter/material.dart';
import '../../core/models/inquiry.dart';
import '../../core/services/inquiry_service.dart';
import '../../core/utils/format.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.orderId,
    required this.orderNo,
    required this.myId,
    required this.myRole,
  });

  final String orderId;
  final String orderNo;
  final String myId;
  final String myRole; // 'operator' | 'partner'

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _markAsRead();
  }

  Future<void> _markAsRead() async {
    await InquiryService.markAsRead(widget.orderId, widget.myRole);
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    
    InquiryService.sendMessage(
      orderId: widget.orderId,
      senderId: widget.myId,
      senderRole: widget.myRole,
      text: text,
    );
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('문의하기', style: TextStyle(fontSize: 16)),
            Text('발주번호 ${widget.orderNo}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: InquiryService.getMessages(widget.orderId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!;
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('문의 사항을 입력해 주세요.',
                        style: TextStyle(color: Color(0xFF8A8880))),
                  );
                }
                
                // 메시지가 오면 읽음 처리 시도
                _markAsRead();

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.senderId == widget.myId;
                    return _MessageBubble(msg: msg, isMe: isMe);
                  },
                );
              },
            ),
          ),
          _inputArea(),
        ],
      ),
    );
  }

  Widget _inputArea() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E5E0))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: '메시지를 입력하세요...',
                border: InputBorder.none,
                isDense: true,
              ),
              maxLines: null,
            ),
          ),
          IconButton(
            onPressed: _send,
            icon: const Icon(Icons.send, color: Color(0xFF185FA5)),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg, required this.isMe});

  final ChatMessage msg;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isMe) ...[
            _readStatus(),
            const SizedBox(width: 4),
            _timeLabel(),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF185FA5) : const Color(0xFFF5F4EF),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(isMe ? 12 : 0),
                  bottomRight: Radius.circular(isMe ? 0 : 12),
                ),
              ),
              child: Text(
                msg.text,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          if (!isMe) ...[
            const SizedBox(width: 8),
            _timeLabel(),
          ],
        ],
      ),
    );
  }

  Widget _timeLabel() {
    return Text(
      formatListTime(msg.createdAt.toDate()),
      style: const TextStyle(fontSize: 10, color: Color(0xFF8A8880)),
    );
  }

  Widget _readStatus() {
    if (!isMe) return const SizedBox.shrink();
    return Text(
      msg.isRead ? '읽음' : '1',
      style: TextStyle(
        fontSize: 10,
        color: msg.isRead ? const Color(0xFF8A8880) : Colors.orange,
        fontWeight: msg.isRead ? FontWeight.normal : FontWeight.bold,
      ),
    );
  }
}
