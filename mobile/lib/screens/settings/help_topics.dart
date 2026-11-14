class HelpItem {
  const HelpItem({required this.question, required this.answer});

  final String question;
  final String answer;
}

class HelpTopic {
  const HelpTopic({
    required this.id,
    required this.title,
    required this.items,
  });

  final String id;
  final String title;
  final List<HelpItem> items;
}

const safetyHelpPreview =
    'Restrict stops a direct message both ways and keeps the history. '
    'Their posts stay off your Home and Discover feeds, and you do not see their last seen, typing, or read receipts. '
    'You can still open their profile. '
    'Block hides each of you from the other, including search. Their profile looks the same as an account that is not there. '
    'You can unblock them from Settings. '
    'A trip or group someone else created can still include both of you.';

const helpTopics = <HelpTopic>[
  HelpTopic(
    id: 'safety',
    title: 'Restrict and Block',
    items: [
      HelpItem(
        question: 'What does Restrict do?',
        answer:
            'Restrict stops a direct message in both directions. Neither of you can send a new message, and the existing chat stays so you can both still read it. Typing and read receipts stop in that direct message too. Their posts stay off your Home and Discover feeds. You can still open their profile and see those posts there. You do not see their last seen, typing, or read receipts. They can still see yours outside a direct message. Group chats and trip chats still accept messages. Restrict does not hide a profile or stop a follow.',
      ),
      HelpItem(
        question: 'What does Block do?',
        answer:
            'Block includes Restrict, in both directions. Search does not list either of you. Their profile looks the same as an account that is not there: no name, photo, trips, or posts. You see Unblock on their profile and in Settings under Blocked. They do not see that they were blocked. Follows are removed in both directions and are not restored when you unblock. Unblock brings their posts and profile back. Neither of you sees the other\'s last seen, typing, or read receipts. Neither of you can add the other to a trip or a group chat that you created. A trip or group that someone else created can include both of you. People already on a trip or in a chat stay there.',
      ),
      HelpItem(
        question: 'Where can I restrict or block someone?',
        answer:
            'Open the menu on their profile, the info button in a direct message, the member menu in a group or trip chat, or the menu on Manage Participants. Settings lists the people you blocked and the people you restricted. You can undo only your own action. If you have blocked someone, unblock them before you can restrict them instead.',
      ),
    ],
  ),
  HelpTopic(
    id: 'account',
    title: 'Account',
    items: [
      HelpItem(
        question: 'How do I sign in?',
        answer:
            'Sign in with your email or your username, and your password. You can also sign in with Google. A Google account may ask you to choose a username before the profile is ready. A wrong password, a missing account, and a Google-only account that has no password all show the same message, so the app does not reveal which accounts exist.',
      ),
      HelpItem(
        question: 'What are the name and password rules?',
        answer:
            'A username is 3 to 30 characters: letters, numbers, and underscores, stored in lowercase. A bio can be up to 200 characters. A password is 8 to 128 characters and needs one lowercase letter, one uppercase letter, and one digit.',
      ),
      HelpItem(
        question: 'How do I change my password?',
        answer:
            'Settings sends a reset link to your email. The link lasts 15 minutes and works once. If the email is not on an account, the app still says a link was sent. Resetting the password signs out your other sessions.',
      ),
      HelpItem(
        question: 'What does deleting my account do?',
        answer:
            'Delete account clears your profile. You can sign up again later with the same email. You cannot delete the account while a trip still shows that you owe money or are owed money.',
      ),
    ],
  ),
  HelpTopic(
    id: 'privacy',
    title: 'Privacy and following',
    items: [
      HelpItem(
        question: 'What is a private account?',
        answer:
            'A public account can be followed immediately. A private account asks you to approve each follow. Until you approve, that person does not see your trips the way a follower does. Switch this in Settings under Private account.',
      ),
      HelpItem(
        question: 'How do follow requests work?',
        answer:
            'On a public profile, Follow starts at once and they are notified. On a private profile, Follow sends a request. They accept or reject it from Follow requests. You can cancel a request that is still waiting. After a rejection you can ask again. You cannot follow yourself.',
      ),
      HelpItem(
        question: 'Who can see a private profile?',
        answer:
            'Someone who does not follow you gets a private-profile message instead of your bio. Follower and following lists stay hidden unless you follow each other. Your name can still appear in search. If your account is private, you can add or invite someone to your trip only when they already follow you.',
      ),
    ],
  ),
  HelpTopic(
    id: 'trips',
    title: 'Trips, start, and end',
    items: [
      HelpItem(
        question: 'When does a trip start?',
        answer:
            'If you leave the start empty, the trip starts now and is ongoing. A start in the future is upcoming until that time. You can own one active trip. Joining someone else’s trip does not count. Starting another one asks you to end the trip you already own, and that replacement does not create a final post.',
      ),
      HelpItem(
        question: 'When does a trip end by itself?',
        answer:
            'Leave the end empty and the trip stays open until you end it. A date with no time lasts through 11:59 PM in the time zone you picked. A date with a time ends at that moment. An hourly check, and opening the trip, both apply those times, so you do not have to wait for the next hour. An open-ended trip is never ended for you.',
      ),
      HelpItem(
        question: 'What happens when I end a trip?',
        answer:
            'You can end an upcoming or ongoing trip. Ending an ongoing trip prepares a final post. Ending an upcoming trip does not. After it has ended, you can move the end later only if a final post does not already exist. The start can change only while the trip is still upcoming.',
      ),
      HelpItem(
        question: 'What do Solo, Group, and the moods mean?',
        answer:
            'If you do not pick a type, the trip stays Solo until a second person joins, then it becomes a Group. If you pick Solo, Group, Couple, or Family, that choice stays. Moods are Relaxed, Adventure, Spiritual, Cultural, Party, and Mixed.',
      ),
    ],
  ),
  HelpTopic(
    id: 'members',
    title: 'Trip members',
    items: [
      HelpItem(
        question: 'Who can add someone?',
        answer:
            'Only the trip owner can add a person or send an invitation. There is no request to join. The owner can cancel an invitation that is still waiting. The person invited accepts or rejects it from Trip invitations. Accepting adds them, and a Solo trip can become a Group.',
      ),
      HelpItem(
        question: 'Can I leave, and can the owner remove me?',
        answer:
            'You can leave a trip you do not own. You choose whether your thread posts stay or are removed. Removal of your posts is only while the trip is ongoing. The owner can remove someone else. Leave and removal both wait if that person’s trip balance is not zero.',
      ),
    ],
  ),
  HelpTopic(
    id: 'thread',
    title: 'The trip thread',
    items: [
      HelpItem(
        question: 'What can I post?',
        answer:
            'A thread post is text, a photo or video, or a location. A location needs a place. Tag a member with their username, or use @all for everyone else on the trip. Check-in posts are not part of the thread.',
      ),
      HelpItem(
        question: 'How long can I edit or delete a post?',
        answer:
            'You can edit your own text for 15 minutes, and only while the trip is ongoing. Photos, videos, and locations are not edited in place. The trip owner can edit any text post while the trip is ongoing. You or the owner can delete a post while the trip is ongoing. Deleting it also removes its likes, comments, and tags.',
      ),
    ],
  ),
  HelpTopic(
    id: 'chats',
    title: 'Chats',
    items: [
      HelpItem(
        question: 'What kinds of chats are there?',
        answer:
            'A direct message is one room for two people. Starting it again opens the same room. A group can hold 16 people, including those already in it. Each trip has one chat named after the trip. The trip owner is an admin of that chat.',
      ),
      HelpItem(
        question: 'What can an admin do?',
        answer:
            'An admin can rename the chat, change its photo, add or remove members, and promote a member to admin. Only admins can do those things. If you are the only admin and other people are still in the chat, promote someone before you leave.',
      ),
      HelpItem(
        question: 'How long can I edit or delete a message?',
        answer:
            'You can edit or delete your own message for 15 minutes. A message can be up to 512 characters. A deleted message stays in the chat as deleted, so the gap in the conversation remains. Sending is limited to 30 messages a minute.',
      ),
      HelpItem(
        question: 'Is leaving a chat the same as leaving a trip?',
        answer:
            'No. Leaving a trip chat keeps you on the trip. Leaving the trip does not put you back into a chat you already left. Adding someone to the trip adds them to the trip chat, unless they had already left that chat.',
      ),
    ],
  ),
  HelpTopic(
    id: 'comments',
    title: 'Comments, likes, and notifications',
    items: [
      HelpItem(
        question: 'How long can I edit or delete a comment?',
        answer:
            'You can edit your own comment for 15 minutes. A comment can be up to 250 characters. You can delete your own comment at any time. The owner of the trip post or thread entry can delete a comment on it. Replies are one level deep.',
      ),
      HelpItem(
        question: 'What shows up in notifications?',
        answer:
            'Notifications cover likes, comments, replies, tags, and follows on a public account. You are not notified when you like your own post. Follow requests and trip invitations open from their own screens. The unread count does not include follow requests. There is no push notification.',
      ),
    ],
  ),
  HelpTopic(
    id: 'discover',
    title: 'Home, Discover, and search',
    items: [
      HelpItem(
        question: 'What is on Home?',
        answer:
            'Home shows published final posts from you, from people you follow, and from public accounts. A private author’s post appears when it is yours or you follow them. Happening now shows ongoing trips that you or someone you follow is on. Your own trip is listed first.',
      ),
      HelpItem(
        question: 'What is on Discover?',
        answer:
            'Discover shows other people’s ongoing and ended trips. Upcoming trips stay off Discover. You see a trip when you follow the owner or the owner is public. People you follow come first, then trips with more posts and members, then ongoing before ended. Search matches the title, description, the owner’s name, and destinations, up to 80 characters.',
      ),
      HelpItem(
        question: 'How does people search work?',
        answer:
            'Search matches a username or a name and leaves you out of the results. Private accounts are not hidden from search. Each result shows whether you follow them and whether they follow you.',
      ),
    ],
  ),
  HelpTopic(
    id: 'final-posts',
    title: 'Final posts',
    items: [
      HelpItem(
        question: 'When is a final post created?',
        answer:
            'Each person on the trip gets their own final post. It is created when an ongoing trip ends, whether you end it or the scheduled end arrives. Ending an upcoming trip does not create one. Either ending leaves an unpublished draft with that person\'s photos. Generating it again does not overwrite edits.',
      ),
      HelpItem(
        question: 'How do I publish it?',
        answer:
            'Edit the summary, caption, cover, and up to 12 photos. The picker shows the order you chose. Publish needs a summary of at least 50 characters and at least one photo or a cover. Ending the trip does not publish the post. Only a published post appears on Home and on its link. You can still edit it after publishing, and you can delete it.',
      ),
    ],
  ),
  HelpTopic(
    id: 'money',
    title: 'Trip money',
    items: [
      HelpItem(
        question: 'What does trip money record?',
        answer:
            'It is a shared ledger, not a payment app. Nothing is charged to a card. Amounts are in the trip currency. The owner chooses the currency before the first expense, and it stays fixed after that. Everyone on the trip, including the owner, can be part of a split.',
      ),
      HelpItem(
        question: 'How do splits and settle-up work?',
        answer:
            'A split can be equal, exact amounts, percents, or shares. A positive balance means the trip owes that person. A negative balance means they owe the trip. Only the person who is owed money can mark a transfer as paid, and only for the amount the app suggests. A recorded payment stays. You cannot leave, be removed, or delete your account while your balance is not zero.',
      ),
      HelpItem(
        question: 'Who can see the trip total?',
        answer:
            'Members can see the total on the trip. On Discover, the total is hidden unless the owner turns on Show spend on Discover.',
      ),
    ],
  ),
  HelpTopic(
    id: 'media',
    title: 'Photos, video, and maps',
    items: [
      HelpItem(
        question: 'What can I upload?',
        answer:
            'Photos can be JPEG, PNG, or GIF. Videos can be MP4, MOV, or AVI, up to 50 MB and 10 minutes. You can pick up to 10 files at a time. The app asks for the camera, photos, or videos when you use them, not when it opens. You can delete your own uploads.',
      ),
      HelpItem(
        question: 'Where do shared photos open?',
        answer:
            'A chat’s details show recent photos and videos, then a grid that fits more columns on a wider screen. The same viewer opens a chat attachment and a thread photo or video. You can swipe by date, play and pause, loop, change speed, and skip five seconds.',
      ),
      HelpItem(
        question: 'How do maps and location work?',
        answer:
            'Place search uses Mapbox. A pin you drop is named from your phone. Location is used only while the map is open. The app does not track you in the background. On the web, the browser asks for location.',
      ),
    ],
  ),
];
