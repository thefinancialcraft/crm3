import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final bool isSmall;

  const AppLogo({super.key, this.isSmall = false});

  @override
  Widget build(BuildContext context) {
    // Colors
    const primaryColor = Color(0xFF4B33E8);
    const darkTextColor = Color.fromARGB(255, 38, 50, 56);
    const whiteColor = Colors.white;

    // Sizes based on logic:
    // isSmall ? 'h-7 w-7' (28px) : 'h-[35px] w-[35px]'
    final double iconBoxSize = isSmall ? 28.0 : 35.0;

    // Icon size approximation. Tailwind text-xs is 12px, text-base is 16px.
    // The icon is text in the React code (<i class=...>), so wrapping font size determines icon size.
    final double iconSize = isSmall ? 12.0 : 16.0;

    // Text Sizes
    // isSmall ? 'text-2xl' (24px) : 'text-3xl' (30px)
    // ignoring md: breakpoint for mobile-first Flutter implementation default
    final double textSize = isSmall ? 24.0 : 30.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Icon Container
        Container(
          width: iconBoxSize,
          height: iconBoxSize,
          decoration: const BoxDecoration(
            color: primaryColor, // #4b33e8
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.phone_in_talk, // Approximation of fi-rr-tty-answer
            color: whiteColor,
            size:
                iconSize +
                4, // Adjusting slightly as Flutter Icons usually need more padding/size to look proportionate to text
          ),
        ),
        const SizedBox(width: 8.0), // gap-2 -> 8px
        // Text Group
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'tfc',
              style: TextStyle(
                color: darkTextColor, // rgb(38, 50, 56)
                fontSize: textSize,
                fontWeight: FontWeight.w900, // font-[900]
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(width: 2.0), // gap-[2px]
            Text(
              'Nexus',
              style: TextStyle(
                color: primaryColor, // #4b33e8
                fontSize: textSize,
                fontWeight: FontWeight.w300, // font-[300]
                fontFamily: 'Roboto',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
