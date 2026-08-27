//
//  AskView.swift
//  sheRuntime
//
//  问问页（问关于你自己的问题）。静态页面 + 假数据。
//  点建议问题或发送，会显示一段示例回答（假的，等接 AI 后替换）。
//  照产品原型 她律原型01.html 的 Ask 页。
//

import SwiftUI

struct AskView: View {
    private let bg = Color(red: 0.957, green: 0.957, blue: 0.937)
    @State private var inputText = ""
    @State private var showAnswer = false

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(C.t("ask.eyebrow")).font(.caption2).fontWeight(.bold)
                            .foregroundStyle(.secondary).tracking(1.5)
                        Text(C.t("ask.title")).font(.system(size: 34, weight: .bold))
                        Text(C.t("ask.subtitle")).font(.footnote).foregroundStyle(.secondary)

                        heroCard

                        VStack(spacing: 8) {
                            ForEach(AskMock.suggestions, id: \.self) { q in
                                Button {
                                    inputText = q
                                    withAnimation { showAnswer = true }
                                } label: {
                                    Text(q).font(.footnote)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(14)
                                        .background(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 18))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.primary)
                            }
                        }

                        if showAnswer { answerCard }

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }

                inputBar
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(C.t("ask.heroSmall").uppercased()).font(.caption2).fontWeight(.bold)
                .foregroundStyle(.white.opacity(0.6)).tracking(1)
            Text(C.t("ask.heroTitle")).font(.title2).fontWeight(.semibold)
                .foregroundStyle(.white)
            Text(C.t("ask.heroBody")).font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private var answerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(C.t("ask.answerLabel").uppercased()).font(.caption2)
                .foregroundStyle(.secondary).tracking(0.5)
            Text(AskMock.sampleAnswer).font(.footnote).lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(C.t("ask.inputPlaceholder"), text: $inputText)
                .padding(12)
                .submitLabel(.send)
                .onSubmit {
                    withAnimation { showAnswer = true }
                }
            Button {
                withAnimation { showAnswer = true }
            } label: {
                Image(systemName: "arrow.up")
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(7)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
}

#Preview { AskView() }
