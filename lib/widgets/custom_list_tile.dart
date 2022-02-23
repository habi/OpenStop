import 'package:flutter/material.dart';

class CustomListTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final void Function()? onTap;
  final bool isThreeLine;

  const CustomListTile({
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.trailingIcon,
    this.onTap,
    this.isThreeLine = false,
    Key? key}) : super(key: key);


  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      isThreeLine: isThreeLine,
      // used to vertically center the icon
      leading: SizedBox(
        height: double.infinity,
        child: Icon(leadingIcon),
      ),
      trailing: SizedBox(
        height: double.infinity,
        child: Icon(
          trailingIcon,
          size: 16,
          color: Theme.of(context).iconTheme.color!.withOpacity(0.20)
        ),
      ),
      onTap: onTap,

    );
  }
}
