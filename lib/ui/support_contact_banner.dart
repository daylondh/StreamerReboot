part of '../app.dart';

class _SupportContactBanner extends StatelessWidget {
  const _SupportContactBanner({required this.session});

  final StreamSession session;

  @override
  Widget build(BuildContext context) {
    final name = session.supportContactName.isEmpty
        ? '<name>'
        : session.supportContactName;
    final phone = session.supportContactPhone.isEmpty
        ? '<phone number>'
        : session.supportContactPhone;
    return Semantics(
      label: 'Software support contact',
      child: Text(
        'If you have any problems with this software, contact $name at $phone',
        key: const Key('support-contact-message'),
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: Colors.black54),
      ),
    );
  }
}
